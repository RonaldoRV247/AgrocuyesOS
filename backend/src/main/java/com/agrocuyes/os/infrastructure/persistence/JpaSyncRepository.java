package com.agrocuyes.os.infrastructure.persistence;

import com.agrocuyes.os.application.sync.port.SyncRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;

import java.util.Optional;
import java.util.UUID;

/**
 * Adaptador JPA del puerto SyncRepository, generico por tipo de entidad.
 *
 * Una sola implementacion cubre las 6 entidades sincronizables porque la
 * operacion es siempre la misma sobre la PK: SELECT ... FOR UPDATE, INSERT y
 * UPDATE. Evita media docena de clases espejo sin perder tipado (el tipo se
 * fija en el @Bean de SyncConfig).
 */
public class JpaSyncRepository<E> implements SyncRepository<E> {

    private final EntityManager entityManager;
    private final Class<E> entityType;

    public JpaSyncRepository(EntityManager entityManager, Class<E> entityType) {
        this.entityManager = entityManager;
        this.entityType = entityType;
    }

    /** FOR UPDATE sobre la PK: el read-modify-write del arbitraje LWW es atomico. */
    @Override
    public Optional<E> loadForUpdate(UUID id) {
        return Optional.ofNullable(entityManager.find(entityType, id, LockModeType.PESSIMISTIC_WRITE));
    }

    /**
     * persist() y NO merge(): la PK la trajo el dispositivo, asi que "id no nulo"
     * no significa "la fila ya existe". merge() sobre estas entidades degenera
     * en un UPDATE de 0 filas.
     */
    @Override
    public E insert(E entity) {
        entityManager.persist(entity);
        return entity;
    }

    @Override
    public E update(E entity) {
        return entityManager.merge(entity);
    }
}
