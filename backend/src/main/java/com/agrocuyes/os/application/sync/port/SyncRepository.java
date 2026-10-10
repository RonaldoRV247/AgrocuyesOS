package com.agrocuyes.os.application.sync.port;

import java.util.Optional;
import java.util.UUID;

/**
 * Slot de persistencia que necesita un handler de sync.
 * Definido en la capa de aplicacion (puerto) e implementado en infraestructura.
 */
public interface SyncRepository<E> {

    /**
     * Carga la fila con bloqueo pesimista (SELECT ... FOR UPDATE).
     * Serializa los reintentos concurrentes del mismo registro provenientes de
     * dos dispositivos, para que el read-modify-write del LWW sea atomico.
     */
    Optional<E> loadForUpdate(UUID id);

    /**
     * Alta de una entidad nueva cuyo id ya puso el dispositivo.
     *
     * Debe ser un metodo distinto de {@link #update}: con PK asignada por el
     * cliente y sin @Version, un merge() sobre una entidad "nueva" la hace ver
     * como detached y Hibernate emite UPDATE sobre una fila que no existe
     * (OptimisticLockException). El arbitraje LWW ya sabe en que rama esta.
     */
    E insert(E entity);

    /** Persiste la sobrescritura de una entidad ya cargada/bloqueada. */
    E update(E entity);
}
