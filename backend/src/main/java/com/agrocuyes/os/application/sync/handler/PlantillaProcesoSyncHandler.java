package com.agrocuyes.os.application.sync.handler;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRef;
import com.agrocuyes.os.application.sync.port.EntityTypes;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.application.sync.service.LwwSyncHandler;
import com.agrocuyes.os.domain.tasks.PlantillaProceso;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.LongSupplier;

/**
 * Catalogo dinamico de procesos. Un handler dedicado porque el alta de tipos
 * nueva (manual o por IA) sigue el mismo camino de sync que lo demas.
 */
@Component
public class PlantillaProcesoSyncHandler extends LwwSyncHandler<PlantillaProceso> {

    public static final String F_NOMBRE = "nombre";
    public static final String F_METADATA = "metadata";
    public static final String F_ACTIVO = "activo";

    public PlantillaProcesoSyncHandler(SyncRepository<PlantillaProceso> repository, LongSupplier syncClock) {
        super(repository, syncClock);
    }

    @Override
    public String entity() {
        return EntityTypes.PLANTILLA_PROCESO;
    }

    @Override
    protected PlantillaProceso create(UUID id, long incomingUpdatedAt, SyncChange change) {
        String nombre = change.string(F_NOMBRE);
        if (nombre == null || nombre.isBlank()) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_NOMBRE));
        }
        return PlantillaProceso.crear(incomingUpdatedAt, id, nombre, change.jsonMap(F_METADATA));
    }

    @Override
    protected void overwrite(PlantillaProceso existing, long incomingUpdatedAt, SyncChange change) {
        Boolean activo = change.bool(F_ACTIVO);
        existing.aplicarDesde(incomingUpdatedAt, change.string(F_NOMBRE), change.jsonMap(F_METADATA),
                activo == null || activo);
    }

    @Override
    protected SyncRef snapshot(PlantillaProceso entity) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put(F_NOMBRE, entity.getNombre());
        payload.put(F_METADATA, entity.getMetadata());
        payload.put(F_ACTIVO, entity.isActivo());
        return new SyncRef(entity(), entity.getId().toString(), entity.getUpdatedAt(),
                entity.isDeleted(), payload);
    }
}
