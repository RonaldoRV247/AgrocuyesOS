package com.agrocuyes.os.application.sync;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRequestDto;
import com.agrocuyes.os.application.sync.dto.SyncResponseDto;
import com.agrocuyes.os.application.sync.dto.SyncResultDto;
import com.agrocuyes.os.application.sync.dto.SyncStatus;
import com.agrocuyes.os.application.sync.handler.RegistroActividadSyncHandler;
import com.agrocuyes.os.application.sync.port.EntityTypes;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.application.sync.service.SyncService;
import com.agrocuyes.os.domain.shared.SyncableEntity;
import com.agrocuyes.os.domain.tasks.RegistroActividad;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Arbitraje Last Write Wins del SyncService sobre registro_actividad.
 * Sin Spring ni Postgres: un repositorio en memoria hace visible el estado
 * exacto que quedo persistido despues de cada veredicto.
 */
class SyncServiceLwwTest {

    private static final long T0 = 1_700_000_000_000L;

    private final UUID registroId = UUID.randomUUID();
    private final UUID terrenoId = UUID.randomUUID();
    private final UUID plantillaId = UUID.randomUUID();

    private final AtomicLong serverNow = new AtomicLong(T0 + 60_000L);
    private InMemorySyncRepository<RegistroActividad> repository;
    private SyncService syncService;

    @BeforeEach
    void setUp() {
        repository = new InMemorySyncRepository<>();
        var handler = new RegistroActividadSyncHandler(repository, serverNow::get);
        syncService = new SyncService(List.of(handler), serverNow::get);
    }

    @Test
    @DisplayName("id desconocido => INSERT respeta el UUID traido por el dispositivo")
    void insertUsesClientSuppliedUuid() {
        var result = push(upsert(T0, Map.of("insumo", "semilla_maiz", "kg_aplicados", 12)));

        assertThat(result.status()).isEqualTo(SyncStatus.INSERTED);
        assertThat(repository.stored.get(registroId)).isNotNull();
        assertThat(repository.stored.get(registroId).getId()).isEqualTo(registroId);
        assertThat(repository.stored.get(registroId).getClientUuid()).isEqualTo(registroId);
        assertThat(repository.stored.get(registroId).getUpdatedAt()).isEqualTo(T0);
    }

    @Test
    @DisplayName("updated_at entrante MAYOR => sobrescribe fila y metadata JSONB")
    void newerIncomingOverwrites() {
        push(upsert(T0, Map.of("insumo", "semilla_maiz")));

        var result = push(upsert(T0 + 1_000, Map.of("insumo", "semilla_maiz", "kg_aplicados", 15)));

        assertThat(result.status()).isEqualTo(SyncStatus.APPLIED);
        var stored = repository.stored.get(registroId);
        assertThat(stored.getUpdatedAt()).isEqualTo(T0 + 1_000);
        assertThat(stored.getMetadata()).containsEntry("kg_aplicados", 15);
        assertThat(stored.getCreatedAt()).isEqualTo(T0);
    }

    @Test
    @DisplayName("updated_at entrante MENOR => STALE, la BD no se toca y se devuelve la version vigente")
    void olderIncomingLosesAndReturnsServerState() {
        push(upsert(T0 + 5_000, Map.of("insumo", "urea")));

        var result = push(upsert(T0 + 1_000, Map.of("insumo", "glifosato")));

        assertThat(result.status()).isEqualTo(SyncStatus.STALE);
        assertThat(result.serverUpdatedAt()).isEqualTo(T0 + 5_000);
        assertThat(result.serverPayload()).containsEntry("metadata", Map.of("insumo", "urea"));
        assertThat(repository.stored.get(registroId).getMetadata()).containsEntry("insumo", "urea");
    }

    @Test
    @DisplayName("empate de updated_at => DUPLICATE: el reintento de la cola offline no duplica datos")
    void equalTimestampIsIdempotent() {
        push(upsert(T0, Map.of("insumo", "urea")));

        var result = push(upsert(T0, Map.of("insumo", "urea")));

        assertThat(result.status()).isEqualTo(SyncStatus.DUPLICATE);
        assertThat(repository.writeCount).isEqualTo(1);
    }

    @Test
    @DisplayName("delete con updated_at mayor => TOMBSTONED (la fila sobrevive como marcador)")
    void deleteNewerTombstones() {
        push(upsert(T0, Map.of("insumo", "urea")));

        var result = push(new SyncChange(EntityTypes.REGISTRO_ACTIVIDAD, registroId.toString(),
                SyncChange.OP_DELETE, T0 + 2_000, null));

        assertThat(result.status()).isEqualTo(SyncStatus.TOMBSTONED);
        assertThat(repository.stored.get(registroId).isDeleted()).isTrue();
        assertThat(repository.stored.get(registroId).getDeletedAt()).isEqualTo(T0 + 2_000);
    }

    @Test
    @DisplayName("upsert sobre un tombstone => REJECTED_DELETED: los borrados no resucitan")
    void tombstoneIsSticky() {
        push(upsert(T0, Map.of("insumo", "urea")));
        push(new SyncChange(EntityTypes.REGISTRO_ACTIVIDAD, registroId.toString(),
                SyncChange.OP_DELETE, T0 + 2_000, null));

        var result = push(upsert(T0 + 3_000, Map.of("insumo", "semilla")));

        assertThat(result.status()).isEqualTo(SyncStatus.REJECTED_DELETED);
        assertThat(repository.stored.get(registroId).isDeleted()).isTrue();
        assertThat(repository.stored.get(registroId).getUpdatedAt()).isEqualTo(T0 + 2_000);
    }

    @Test
    @DisplayName("updated_at del futuro mas alla de la tolerancia => REJECTED (no envenena el reloj)")
    void rejectsPoisonedClock() {
        var result = push(upsert(serverNow.get() + 10 * 60_000L, Map.of("insumo", "urea")));

        assertThat(result.status()).isEqualTo(SyncStatus.REJECTED);
        assertThat(result.error()).contains("INVALID_PAYLOAD");
        assertThat(repository.stored).isEmpty();
    }

    @Test
    @DisplayName("payload incompleto => REJECTED y el resto del lote se procesa igual")
    void invalidPayloadDoesNotAbortBatch() {
        var good = upsert(T0, Map.of("insumo", "urea"));
        var bad = new SyncChange(EntityTypes.REGISTRO_ACTIVIDAD, UUID.randomUUID().toString(),
                SyncChange.OP_UPSERT, T0, new LinkedHashMap<>(Map.of("metadata", Map.of())));

        SyncResponseDto response = syncService.pushChanges(
                new SyncRequestDto("device-celular-01", List.of(bad, good)));

        assertThat(response.accepted()).isEqualTo(1);
        assertThat(response.rejected()).isEqualTo(1);
        assertThat(response.results().getFirst().status()).isEqualTo(SyncStatus.REJECTED);
        assertThat(response.results().get(1).status()).isEqualTo(SyncStatus.INSERTED);
    }

    @Test
    @DisplayName("entidad no soportada => REJECTED explicito (el contrato no se rompe)")
    void unknownEntityIsRejected() {
        var response = syncService.pushChanges(new SyncRequestDto("device-1",
                List.of(new SyncChange("invernadero", UUID.randomUUID().toString(),
                        SyncChange.OP_UPSERT, T0, Map.of()))));

        assertThat(response.results().getFirst().status()).isEqualTo(SyncStatus.REJECTED);
        assertThat(response.results().getFirst().error()).contains("unsupported entity");
    }

    @Test
    @DisplayName("el lote reporta el reloj del server para que el dispositivo mida su deriva")
    void responseCarriesServerTimestamp() {
        var response = syncService.pushChanges(new SyncRequestDto("device-1", List.of(upsert(T0, Map.of()))));

        assertThat(response.serverTimestamp()).isEqualTo(T0 + 60_000L);
        assertThat(response.deviceId()).isEqualTo("device-1");
    }

    // ---- helpers ----------------------------------------------------------

    private SyncResultDto push(SyncChange change) {
        return syncService.pushChanges(new SyncRequestDto("device-celular-01", List.of(change)))
                .results().getFirst();
    }

    private SyncChange upsert(long updatedAt, Map<String, Object> metadata) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put(RegistroActividadSyncHandler.F_TERRENO_ID, terrenoId.toString());
        payload.put(RegistroActividadSyncHandler.F_PLANTILLA_ID, plantillaId.toString());
        payload.put(RegistroActividadSyncHandler.F_FECHA_REALIZADA, LocalDate.of(2026, 10, 10).toString());
        payload.put(RegistroActividadSyncHandler.F_METADATA, new LinkedHashMap<>(metadata));
        return new SyncChange(EntityTypes.REGISTRO_ACTIVIDAD, registroId.toString(),
                SyncChange.OP_UPSERT, updatedAt, payload);
    }

    /** Repositorio de prueba con semantica explicita de alta vs actualizacion. */
    static class InMemorySyncRepository<E extends SyncableEntity> implements SyncRepository<E> {
        final Map<UUID, E> stored = new LinkedHashMap<>();
        int writeCount;

        @Override
        public Optional<E> loadForUpdate(UUID id) {
            return Optional.ofNullable(stored.get(id));
        }

        @Override
        public E insert(E entity) {
            writeCount++;
            stored.put(entity.getId(), entity);
            return entity;
        }

        @Override
        public E update(E entity) {
            writeCount++;
            stored.put(entity.getId(), entity);
            return entity;
        }
    }
}
