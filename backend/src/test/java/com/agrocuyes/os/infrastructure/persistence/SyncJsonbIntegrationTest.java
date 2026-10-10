package com.agrocuyes.os.infrastructure.persistence;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Rebanada vertical real sobre PostgreSQL efimero:
 * HTTP -> SyncService -> handler LWW -> JPA/JSONB -> Flyway V1.
 *
 * Comprueba lo que un mock no puede: que el mapeo jsonb coincide con el DDL
 * (ddl-auto=validate), que las FK diferidas aceptan un lote con el hijo antes
 * que el padre, y que los operadores JSONB (@>, ->>) funcionan sobre lo sincronizado.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
class SyncJsonbIntegrationTest {

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void datasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    private static final long BASE = 1_700_000_000_000L;

    @Autowired
    MockMvc mockMvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    ObjectMapper objectMapper;

    @Test
    @DisplayName("lote offline con FK diferida: el hijo se aplica antes que el padre")
    void acceptsOutOfOrderBatchAndStoresJsonb() throws Exception {
        UUID terrenoId = UUID.randomUUID();
        UUID plantillaId = UUID.randomUUID();
        UUID registroId = UUID.randomUUID();

        // Orden deliberadamente invertido: actividad -> plantilla -> terreno.
        String body = request(List.of(
                registroChange(registroId, terrenoId, plantillaId, BASE,
                        Map.of("insumo", "semilla_maiz", "kg_aplicados", 12, "humedad_pct", 18)),
                change("plantilla_proceso", plantillaId, BASE, Map.of("nombre", "Siembra",
                        "metadata", Map.of("pasos", List.of("surcar", "sembrar", "tapar")))),
                change("terreno", terrenoId, BASE, Map.of("nombre", "Lote Norte", "owner_id",
                        UUID.randomUUID().toString(), "area_m2", 4200.5))
        ));

        mockMvc.perform(post("/api/v1/sync/changes")
                        .contentType("application/json")
                        .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accepted").value(3))
                .andExpect(jsonPath("$.rejected").value(0))
                .andExpect(jsonPath("$.results[0].status").value("INSERTED"));

        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT metadata ->> 'insumo' AS insumo, (metadata ->> 'kg_aplicados')::int AS kg,"
                        + " updated_at, deleted FROM registro_actividad WHERE id = ?", registroId);
        assertThat(row)
                .containsEntry("insumo", "semilla_maiz")
                .containsEntry("kg", 12)
                .containsEntry("updated_at", BASE)
                .containsEntry("deleted", false);

        // Contencion JSONB (lo que usa la busqueda dinamica y el indice GIN).
        Integer hits = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM registro_actividad WHERE metadata @> '{\"insumo\":\"semilla_maiz\"}'::jsonb",
                Integer.class);
        assertThat(hits).isEqualTo(1);
    }

    @Test
    @DisplayName("LWW sobre jsonb: gana el updated_at mayor y la metadata se reemplaza")
    void lastWriteWinsOverwritesJsonb() throws Exception {
        UUID terrenoId = UUID.randomUUID();
        UUID plantillaId = UUID.randomUUID();
        UUID registroId = UUID.randomUUID();

        seedParents(terrenoId, plantillaId);

        pushSync(registroChange(registroId, terrenoId, plantillaId, BASE + 1_000,
                Map.of("insumo", "urea", "kg_aplicados", 5)));

        // Escrito viejos desde otro dispositivo: pierden.
        mockMvc.perform(post("/api/v1/sync/changes")
                        .contentType("application/json")
                        .content(request(List.of(registroChange(registroId, terrenoId, plantillaId, BASE,
                                Map.of("insumo", "glifosato"))))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.results[0].status").value("STALE"))
                .andExpect(jsonPath("$.results[0].server_payload.metadata.insumo").value("urea"))
                .andExpect(jsonPath("$.results[0].server_updated_at").value(BASE + 1_000));

        // Escrito nuevo: gana y pisa el jsonb completo.
        mockMvc.perform(post("/api/v1/sync/changes")
                        .contentType("application/json")
                        .content(request(List.of(registroChange(registroId, terrenoId, plantillaId, BASE + 9_000,
                                Map.of("insumo", "compost", "saco", "S-11", "lote_ai", "IA-2026-10"))))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.results[0].status").value("APPLIED"));

        // Ojo: el operador jsonb "?" se escribe como jsonb_exists() porque el
        // driver JDBC interpreta cada "?" como un placeholder de parametro.
        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT metadata ->> 'insumo' AS insumo, jsonb_exists(metadata, 'kg_aplicados') AS conservo_viejo,"
                        + " updated_at FROM registro_actividad WHERE id = ?", registroId);
        assertThat(row)
                .containsEntry("insumo", "compost")
                .containsEntry("conservo_viejo", false)
                .containsEntry("updated_at", BASE + 9_000);
    }

    @Test
    @DisplayName("tombstone: delete mas nuevo gana y un upsert posterior no resucita la fila")
    void tombstoneWins() throws Exception {
        UUID terrenoId = UUID.randomUUID();
        UUID plantillaId = UUID.randomUUID();
        UUID registroId = UUID.randomUUID();

        seedParents(terrenoId, plantillaId);
        pushSync(registroChange(registroId, terrenoId, plantillaId, BASE, Map.of("insumo", "urea")));
        pushSync(Map.of("entity", "registro_actividad", "id", registroId.toString(), "op", "delete",
                "updated_at", BASE + 5_000));

        assertThat(jdbcTemplate.queryForObject(
                "SELECT deleted FROM registro_actividad WHERE id = ?", Boolean.class, registroId)).isTrue();

        mockMvc.perform(post("/api/v1/sync/changes")
                        .contentType("application/json")
                        .content(request(List.of(registroChange(registroId, terrenoId, plantillaId, BASE + 6_000,
                                Map.of("insumo", "semilla"))))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.results[0].status").value("REJECTED_DELETED"))
                .andExpect(jsonPath("$.results[0].server_deleted").value(true));

        assertThat(jdbcTemplate.queryForObject(
                "SELECT count(*) FROM registro_actividad WHERE id = ?", Integer.class, registroId)).isEqualTo(1);
    }

    // ---- helpers ----------------------------------------------------------

    private void seedParents(UUID terrenoId, UUID plantillaId) throws Exception {
        pushSync(Map.of("entity", "plantilla_proceso", "id", plantillaId.toString(), "op", "upsert",
                "updated_at", BASE, "payload",
                Map.of("nombre", "Fertilizacion", "metadata", Map.of("frecuencia_dias", 20))));
        pushSync(Map.of("entity", "terreno", "id", terrenoId.toString(), "op", "upsert",
                "updated_at", BASE, "payload",
                Map.of("nombre", "Lote Sur", "owner_id", UUID.randomUUID().toString())));
    }

    private Map<String, Object> registroChange(UUID id, UUID terrenoId, UUID plantillaId, long updatedAt,
                                               Map<String, Object> metadata) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("terreno_id", terrenoId.toString());
        payload.put("plantilla_id", plantillaId.toString());
        payload.put("fecha_realizada", LocalDate.of(2026, 10, 9).toString());
        payload.put("metadata", metadata);
        return change("registro_actividad", id, updatedAt, payload);
    }

    private Map<String, Object> change(String entity, UUID id, long updatedAt, Map<String, Object> payload) {
        Map<String, Object> change = new LinkedHashMap<>();
        change.put("entity", entity);
        change.put("id", id.toString());
        change.put("op", "upsert");
        change.put("updated_at", updatedAt);
        change.put("payload", payload);
        return change;
    }

    private void pushSync(Map<String, Object> change) throws Exception {
        pushSync(List.of(change));
    }

    private void pushSync(List<Map<String, Object>> changes) throws Exception {
        mockMvc.perform(post("/api/v1/sync/changes")
                        .contentType("application/json")
                        .content(request(changes)))
                .andExpect(status().isOk());
    }

    private String request(List<Map<String, Object>> changes) throws Exception {
        return objectMapper.writeValueAsString(Map.of(
                "device_id", "device-celular-01",
                "changes", changes));
    }
}
