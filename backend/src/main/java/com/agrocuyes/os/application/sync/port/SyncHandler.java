package com.agrocuyes.os.application.sync.port;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.domain.shared.SyncableEntity;

/**
 * Contrato de resolucion de conflictos por tipo de entidad.
 * Cada core (tareas, crianza) aporta sus handlers y el SyncService los
 * enruta por `entity` sin conocer detalles de persistencia ni de HTTP.
 */
public interface SyncHandler<E extends SyncableEntity> {

    /** Clave de enrutamiento; coincide con el campo `entity` del payload. */
    String entity();

    /** Procesa UN cambio y devuelve como quedo. */
    MergeOutcome apply(SyncChange change);
}
