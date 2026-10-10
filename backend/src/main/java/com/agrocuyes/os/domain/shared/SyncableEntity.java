package com.agrocuyes.os.domain.shared;

import jakarta.persistence.Column;
import jakarta.persistence.Id;
import jakarta.persistence.MappedSuperclass;
import jakarta.persistence.Version;

import java.util.UUID;

/**
 * Base comun de toda entidad sincronizable (Offline-First + Last Write Wins).
 *
 * Invariantes que centraliza:
 *  - PK **asignada**: la trae el dispositivo offline. No hay @GeneratedValue ni
 *    generadores de Hibernate: el id se define antes de salir del cliente y es
 *    inmutable. Solo las altas nacidas en el server (web, seeds) generan uno,
 *    explicitamente en {@link #initIdentity}.
 *  - created_at / updated_at como epoch-millis UTC (BIGINT en Postgres): el
 *    unico reloj que participa en la resolucion de conflictos LWW.
 *  - deleted (tombstone): un borrado es un estado replicable, no la ausencia
 *    de la fila.
 *  - version: ciclo de vida de JPA, no conflicto (ver abajo).
 */
@MappedSuperclass
public abstract class SyncableEntity {

    /**
     * `@Id` sin generador a proposito. Con PK asignada por el cliente, anadir
     * un generador (p.ej. @UuidGenerator) hace que Hibernate clasifique la
     * entidad como "detached con id generado" en cuanto el id viene no nulo, y
     * entonces ni persist() (PersistentObjectException) ni merge() (UPDATE de 0
     * filas) funcionan. La deteccion transient/detached recae en @Version.
     */
    @Id
    @Column(name = "id", columnDefinition = "uuid", updatable = false, nullable = false)
    private UUID id;

    /** updated_at del payload entrante > updated_at en BD => gana el payload. */
    @Column(name = "updated_at", columnDefinition = "bigint", nullable = false)
    private long updatedAt;

    @Column(name = "created_at", columnDefinition = "bigint", nullable = false, updatable = false)
    private long createdAt;

    @Column(name = "deleted", nullable = false)
    private boolean deleted;

    @Column(name = "deleted_at", columnDefinition = "bigint")
    private Long deletedAt;

    /**
     * Contador de ciclo de vida de JPA (nulo => transient => INSERT).
     * NO es el reloj de conflicto: ese es `updated_at`. El bloqueo pesimista por
     * PK ya serializa los writes, asi que en la practica nunca sube por conflicto.
     */
    @Version
    @Column(name = "version", nullable = false)
    private Long version;

    /**
     * Unica ruta de alta: fija la PK (o genera un UUIDv4 si nace en el server) y
     * siembra created_at == updated_at == now.
     */
    protected void initIdentity(UUID idFromClient, long epochMillis) {
        this.id = idFromClient != null ? idFromClient : UUID.randomUUID();
        this.createdAt = epochMillis;
        this.updatedAt = epochMillis;
    }

    /** Regla LWW: solo un timestamp estrictamente mayor pisa el estado actual. */
    public boolean acceptsOverwrite(long incomingUpdatedAt) {
        return incomingUpdatedAt > this.updatedAt;
    }

    /** Aplica un estado entrante y reancla el reloj de la fila. */
    public void touch(long newUpdatedAt) {
        if (newUpdatedAt <= this.updatedAt) {
            throw new IllegalStateException(
                    "LWW violation on %s: new=%d <= current=%d"
                            .formatted(getId(), newUpdatedAt, this.updatedAt));
        }
        this.updatedAt = newUpdatedAt;
    }

    public void softDelete(long atEpochMillis) {
        this.deleted = true;
        this.deletedAt = atEpochMillis;
        touch(atEpochMillis);
    }

    public UUID getId() {
        return id;
    }

    public long getUpdatedAt() {
        return updatedAt;
    }

    public long getCreatedAt() {
        return createdAt;
    }

    public boolean isDeleted() {
        return deleted;
    }

    public Long getDeletedAt() {
        return deletedAt;
    }

    public Long getVersion() {
        return version;
    }
}
