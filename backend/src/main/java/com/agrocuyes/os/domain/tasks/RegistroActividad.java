package com.agrocuyes.os.domain.tasks;

import com.agrocuyes.os.domain.shared.SyncableEntity;
import io.hypersistence.utils.hibernate.type.json.JsonBinaryType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.Type;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Transaccion central del core dinamico de tareas.
 *
 * Que se hizo (PlantillaProceso), donde (Terreno), cuando (fecha_realizada) y
 * CUALES fueron los detalles (metadata JSONB). Los detalles nunca se modelan
 * como columnas: un cambio de formulario en el dispositivo o una ingesta IA no
 * puede exigir un ALTER TABLE.
 */
@Entity
@Table(name = "registro_actividad")
@Getter
@Setter
@NoArgsConstructor
public class RegistroActividad extends SyncableEntity {

    /** UUID generado en el dispositivo: es la clave de idempotencia del sync. */
    @Column(name = "client_uuid", columnDefinition = "uuid", nullable = false, updatable = false)
    private UUID clientUuid;

    /** FK logica a terreno.id. Sin @ManyToOne: el padre puede estar pendiente de sync. */
    @Column(name = "terreno_id", columnDefinition = "uuid", nullable = false)
    private UUID terrenoId;

    /** FK logica a plantilla_proceso.id. */
    @Column(name = "plantilla_id", columnDefinition = "uuid", nullable = false)
    private UUID plantillaId;

    @Column(name = "fecha_realizada", nullable = false)
    private LocalDate fechaRealizada;

    /**
     * JSONB nativo de PostgreSQL.
     * - columnDefinition = "jsonb"  => el DDL de Flyway y el validate de Hibernate coinciden.
     * - JsonBinaryType              => serialize/deserialize a Map y operadores ->>, @>, ?|
     *   sobre la columna sin cargar la fila completa.
     */
    @Type(JsonBinaryType.class)
    @Column(name = "metadata", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> metadata = new LinkedHashMap<>();

    /**
     * Alta local (dispositivo offline o server). El id y el clientUuid los pone
     * el cliente; server nunca reasigna una PK ya emitida.
     */
    public static RegistroActividad crear(long now,
                                          UUID id,
                                          UUID terrenoId,
                                          UUID plantillaId,
                                          LocalDate fechaRealizada,
                                          Map<String, Object> metadata) {
        var registro = new RegistroActividad();
        registro.initIdentity(id, now);
        registro.clientUuid = registro.getId();
        registro.terrenoId = terrenoId;
        registro.plantillaId = plantillaId;
        registro.fechaRealizada = fechaRealizada;
        registro.metadata = metadata == null ? new LinkedHashMap<>() : new LinkedHashMap<>(metadata);
        return registro;
    }

    /** Sobrescrita LWW: el estado entrante reemplaza al almacenado por completo. */
    public void aplicarDesde(long incomingUpdatedAt,
                             UUID terrenoId,
                             UUID plantillaId,
                             LocalDate fechaRealizada,
                             Map<String, Object> metadata) {
        this.terrenoId = terrenoId;
        this.plantillaId = plantillaId;
        this.fechaRealizada = fechaRealizada;
        this.metadata = metadata == null ? new LinkedHashMap<>() : new LinkedHashMap<>(metadata);
        touch(incomingUpdatedAt);
    }
}
