package com.agrocuyes.os.application.sync.port;

import com.agrocuyes.os.application.sync.dto.SyncRef;

import java.util.Map;

/**
 * Resultado del arbitraje LWW sobre un cambio.
 * Sellado a proposito: cada rama obliga al llamador a decidir el estado del
 * registro que devuelve al dispositivo.
 */
public sealed interface MergeOutcome {

    record Inserted(SyncRef ref) implements MergeOutcome {
    }

    /** Gano el payload: sobrescribio la fila. */
    record Applied(SyncRef ref) implements MergeOutcome {
    }

    /**
     * Perdio el payload (updated_at entrante < actual). El servidor devuelve su
     * version vigente para que el dispositivo se reconcilie y descarte su copia.
     */
    record Stale(SyncRef serverState) implements MergeOutcome {
    }

    /** Empate: reintento del mismo cambio. No-op idempotente. */
    record Duplicate(SyncRef ref) implements MergeOutcome {
    }

    /** Borrado propagado (tombstone aplicado). */
    record Tombstoned(SyncRef ref) implements MergeOutcome {
    }

    /** El servidor tenia un tombstone vigente: el alta del dispositivo se descarta. */
    record RejectedDeleted(SyncRef serverState) implements MergeOutcome {
    }

    /** Violacion de invariantes (FK huerfana, clock skew, payload invalido). */
    record Rejected(String reason, Map<String, Object> details) implements MergeOutcome {
    }

    static SyncRef ref(String entity, Object id, long updatedAt, Map<String, Object> payload, boolean deleted) {
        return new SyncRef(entity, String.valueOf(id), updatedAt, deleted, payload);
    }
}
