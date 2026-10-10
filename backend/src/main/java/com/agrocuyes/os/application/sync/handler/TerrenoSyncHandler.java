package com.agrocuyes.os.application.sync.handler;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRef;
import com.agrocuyes.os.application.sync.port.EntityTypes;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.application.sync.service.LwwSyncHandler;
import com.agrocuyes.os.domain.tasks.Terreno;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.LongSupplier;

@Component
public class TerrenoSyncHandler extends LwwSyncHandler<Terreno> {

    public static final String F_NOMBRE = "nombre";
    public static final String F_AREA_M2 = "area_m2";
    public static final String F_LAT = "lat";
    public static final String F_LNG = "lng";
    public static final String F_OWNER_ID = "owner_id";

    public TerrenoSyncHandler(SyncRepository<Terreno> repository, LongSupplier syncClock) {
        super(repository, syncClock);
    }

    @Override
    public String entity() {
        return EntityTypes.TERRENO;
    }

    @Override
    protected Terreno create(UUID id, long incomingUpdatedAt, SyncChange change) {
        String nombre = change.string(F_NOMBRE);
        UUID ownerId = change.uuid(F_OWNER_ID);
        if (nombre == null || nombre.isBlank()) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_NOMBRE));
        }
        if (ownerId == null) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_OWNER_ID));
        }
        Terreno terreno = Terreno.crear(incomingUpdatedAt, id, nombre, ownerId);
        terreno.setAreaM2(change.doubleValue(F_AREA_M2));
        terreno.setLat(change.doubleValue(F_LAT));
        terreno.setLng(change.doubleValue(F_LNG));
        return terreno;
    }

    @Override
    protected void overwrite(Terreno existing, long incomingUpdatedAt, SyncChange change) {
        existing.aplicarDesde(incomingUpdatedAt, change.string(F_NOMBRE),
                change.doubleValue(F_AREA_M2), change.doubleValue(F_LAT), change.doubleValue(F_LNG));
    }

    @Override
    protected SyncRef snapshot(Terreno entity) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put(F_NOMBRE, entity.getNombre());
        payload.put(F_AREA_M2, entity.getAreaM2());
        payload.put(F_LAT, entity.getLat());
        payload.put(F_LNG, entity.getLng());
        payload.put(F_OWNER_ID, entity.getOwnerId());
        return new SyncRef(entity(), entity.getId().toString(), entity.getUpdatedAt(),
                entity.isDeleted(), payload);
    }
}
