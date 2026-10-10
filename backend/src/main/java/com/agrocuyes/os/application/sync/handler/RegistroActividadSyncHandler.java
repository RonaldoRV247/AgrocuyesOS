package com.agrocuyes.os.application.sync.handler;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRef;
import com.agrocuyes.os.application.sync.port.EntityTypes;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.application.sync.service.LwwSyncHandler;
import com.agrocuyes.os.domain.tasks.RegistroActividad;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.LongSupplier;

/**
 * Handler del core dinamico de tareas: el unico con metadata JSONB variable.
 */
@Component
public class RegistroActividadSyncHandler extends LwwSyncHandler<RegistroActividad> {

    public static final String F_TERRENO_ID = "terreno_id";
    public static final String F_PLANTILLA_ID = "plantilla_id";
    public static final String F_FECHA_REALIZADA = "fecha_realizada";
    public static final String F_METADATA = "metadata";

    public RegistroActividadSyncHandler(SyncRepository<RegistroActividad> repository, LongSupplier syncClock) {
        super(repository, syncClock);
    }

    @Override
    public String entity() {
        return EntityTypes.REGISTRO_ACTIVIDAD;
    }

    @Override
    protected RegistroActividad create(UUID id, long incomingUpdatedAt, SyncChange change) {
        LocalDate fecha = change.date(F_FECHA_REALIZADA);
        if (fecha == null) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_FECHA_REALIZADA));
        }
        return RegistroActividad.crear(incomingUpdatedAt, id,
                change.uuid(F_TERRENO_ID), change.uuid(F_PLANTILLA_ID), fecha, change.jsonMap(F_METADATA));
    }

    @Override
    protected void overwrite(RegistroActividad existing, long incomingUpdatedAt, SyncChange change) {
        existing.aplicarDesde(incomingUpdatedAt,
                change.uuid(F_TERRENO_ID),
                change.uuid(F_PLANTILLA_ID),
                change.date(F_FECHA_REALIZADA),
                change.jsonMap(F_METADATA));
    }

    @Override
    protected SyncRef snapshot(RegistroActividad entity) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put(F_TERRENO_ID, entity.getTerrenoId());
        payload.put(F_PLANTILLA_ID, entity.getPlantillaId());
        payload.put(F_FECHA_REALIZADA, entity.getFechaRealizada());
        payload.put(F_METADATA, entity.getMetadata());
        return new SyncRef(entity(), entity.getId().toString(), entity.getUpdatedAt(),
                entity.isDeleted(), payload);
    }
}
