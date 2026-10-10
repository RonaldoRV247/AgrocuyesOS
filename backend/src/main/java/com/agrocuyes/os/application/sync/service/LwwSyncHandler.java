package com.agrocuyes.os.application.sync.service;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRef;
import com.agrocuyes.os.application.sync.port.MergeOutcome;
import com.agrocuyes.os.application.sync.port.SyncHandler;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.domain.shared.SyncableEntity;
import org.springframework.beans.factory.annotation.Value;

import java.time.DateTimeException;
import java.util.Map;
import java.util.UUID;
import java.util.function.LongSupplier;

/**
 * Arbitraje Last Write Wins compartido por todas las entidades sincronizables.
 *
 * La regla vive en UN solo lugar y se aplica en el mismo orden para cualquier
 * core (tareas o crianza):
 *
 *   1. id inexistente              -> INSERT
 *   2. updated_at actual >= nuevo  -> DUPLICATE (empate) o STALE (mas viejo)
 *   3. tombstone vigente           -> REJECTED_DELETED (los borrados no reviven)
 *   4. op == delete                -> TOMBSTONED
 *   5. resto                       -> APPLIED (sobrescritura completa)
 *
 * El bloqueo pesimista por PK (loadForUpdate) evita que dos dispositivos que
 * suben el mismo registro se pisen entre el read y el write.
 */
public abstract class LwwSyncHandler<E extends SyncableEntity> implements SyncHandler<E> {

    /**
     * Tolerancia de reloj de campo (ms): un updated_at "del futuro" se rechaza
     * en lugar de instalar un reloj envenenado que ganaria todos los LWW.
     * Se resuelve desde `agrocuyes.sync.max-clock-skew-ms`; los tests que
     * construyen el handler con `new` conservan el default.
     */
    @Value("${agrocuyes.sync.max-clock-skew-ms:300000}")
    protected long maxClockSkewMs = 300_000L;

    protected final SyncRepository<E> repository;
    protected final LongSupplier clock;

    protected LwwSyncHandler(SyncRepository<E> repository, LongSupplier clock) {
        this.repository = repository;
        this.clock = clock;
    }

    @Override
    public MergeOutcome apply(SyncChange change) {
        final UUID id;
        final long incomingAt;
        try {
            id = change.idAsUuid();
            incomingAt = change.updatedAtOrThrow();
        } catch (IllegalArgumentException | DateTimeException ex) {
            return invalid(change, ex.getMessage());
        }

        long now = clock.getAsLong();
        if (incomingAt > now + maxClockSkewMs) {
            return invalid(change, "updated_at %d is ahead of server time %d by more than %d ms"
                    .formatted(incomingAt, now, maxClockSkewMs));
        }

        E existing = repository.loadForUpdate(id).orElse(null);

        if (existing == null) {
            if (change.isDelete()) {
                return new MergeOutcome.Tombstoned(
                        MergeOutcome.ref(entity(), id, incomingAt, Map.of(), true));
            }
            // El catch cubre SOLO el mapeo payload->entidad. Un error de
            // persistencia debe abortar el lote: Hibernate ya marco la
            // transaccion como rollback-only y ocultarlo produce un commit
            // engañoso.
            final E created;
            try {
                created = create(id, incomingAt, change);
            } catch (IllegalArgumentException | DateTimeException ex) {
                return invalid(change, ex.getMessage());
            }
            return new MergeOutcome.Inserted(snapshot(repository.insert(created)));
        }

        // --- nucleo LWW: la marca de tiempo almacenada es la dueña de la verdad ---
        SyncRef serverRef = snapshot(existing);
        if (!existing.acceptsOverwrite(incomingAt)) {
            // Empate = reintento de la misma cola; menor = el dispositivo traia
            // datos viejos. En ambos casos se devuelve la version del server.
            return existing.getUpdatedAt() == incomingAt
                    ? new MergeOutcome.Duplicate(serverRef)
                    : new MergeOutcome.Stale(serverRef);
        }

        // Borrado logico vigente: un payload mas nuevo NO resucita la fila.
        if (existing.isDeleted()) {
            return new MergeOutcome.RejectedDeleted(serverRef);
        }

        if (change.isDelete()) {
            existing.softDelete(incomingAt);
            return new MergeOutcome.Tombstoned(snapshot(repository.update(existing)));
        }

        try {
            overwrite(existing, incomingAt, change);
        } catch (IllegalArgumentException | DateTimeException ex) {
            return invalid(change, ex.getMessage());
        }
        return new MergeOutcome.Applied(snapshot(repository.update(existing)));
    }

    private MergeOutcome.Rejected invalid(SyncChange change, String message) {
        return new MergeOutcome.Rejected("INVALID_PAYLOAD", Map.of(
                "entity", String.valueOf(change.entity()),
                "id", String.valueOf(change.id()),
                "message", String.valueOf(message)));
    }

    // ---- hooks por entidad ------------------------------------------------

    /** Alta desde un payload; el id lo trae el dispositivo, el server no lo reinventa. */
    protected abstract E create(UUID id, long incomingUpdatedAt, SyncChange change);

    /** Sobrescritura LWW; debe terminar con entity.touch(incomingUpdatedAt). */
    protected abstract void overwrite(E existing, long incomingUpdatedAt, SyncChange change);

    /** Estado autoritativo que se devuelve al cliente para reconciliarse. */
    protected abstract SyncRef snapshot(E entity);
}
