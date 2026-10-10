package com.agrocuyes.os.application.sync.handler;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRef;
import com.agrocuyes.os.application.sync.port.EntityTypes;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.application.sync.service.LwwSyncHandler;
import com.agrocuyes.os.domain.cria.Galpon;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.LongSupplier;

@Component
public class GalponSyncHandler extends LwwSyncHandler<Galpon> {

    public static final String F_NOMBRE = "nombre";
    public static final String F_CAPACIDAD_MAXIMA = "capacidad_maxima";
    public static final String F_OWNER_ID = "owner_id";

    public GalponSyncHandler(SyncRepository<Galpon> repository, LongSupplier syncClock) {
        super(repository, syncClock);
    }

    @Override
    public String entity() {
        return EntityTypes.GALPON;
    }

    @Override
    protected Galpon create(UUID id, long incomingUpdatedAt, SyncChange change) {
        String nombre = change.string(F_NOMBRE);
        UUID ownerId = change.uuid(F_OWNER_ID);
        if (nombre == null || nombre.isBlank()) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_NOMBRE));
        }
        if (ownerId == null) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_OWNER_ID));
        }
        return Galpon.crear(incomingUpdatedAt, id, nombre, ownerId, change.integer(F_CAPACIDAD_MAXIMA));
    }

    @Override
    protected void overwrite(Galpon existing, long incomingUpdatedAt, SyncChange change) {
        existing.aplicarDesde(incomingUpdatedAt, change.string(F_NOMBRE), change.integer(F_CAPACIDAD_MAXIMA));
    }

    @Override
    protected SyncRef snapshot(Galpon entity) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put(F_NOMBRE, entity.getNombre());
        payload.put(F_CAPACIDAD_MAXIMA, entity.getCapacidadMaxima());
        payload.put(F_OWNER_ID, entity.getOwnerId());
        return new SyncRef(entity(), entity.getId().toString(), entity.getUpdatedAt(),
                entity.isDeleted(), payload);
    }
}
