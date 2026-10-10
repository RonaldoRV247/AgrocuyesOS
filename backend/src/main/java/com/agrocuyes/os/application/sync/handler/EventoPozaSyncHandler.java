package com.agrocuyes.os.application.sync.handler;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRef;
import com.agrocuyes.os.application.sync.port.EntityTypes;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.application.sync.service.LwwSyncHandler;
import com.agrocuyes.os.domain.cria.EventoPoza;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.LongSupplier;

/**
 * Transaccion del core de crianza. `tipo_evento` viaja como texto del catalogo
 * dinamico: se sincronizan tipos que la app no conoacia al compilar.
 */
@Component
public class EventoPozaSyncHandler extends LwwSyncHandler<EventoPoza> {

    public static final String F_POZA_ID = "poza_id";
    public static final String F_TIPO_EVENTO = "tipo_evento";
    public static final String F_FECHA_EVENTO = "fecha_evento";
    public static final String F_DETALLES = "detalles";

    public EventoPozaSyncHandler(SyncRepository<EventoPoza> repository, LongSupplier syncClock) {
        super(repository, syncClock);
    }

    @Override
    public String entity() {
        return EntityTypes.EVENTO_POZA;
    }

    @Override
    protected EventoPoza create(UUID id, long incomingUpdatedAt, SyncChange change) {
        String tipo = change.string(F_TIPO_EVENTO);
        LocalDate fecha = change.date(F_FECHA_EVENTO);
        if (tipo == null || tipo.isBlank()) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_TIPO_EVENTO));
        }
        if (change.uuid(F_POZA_ID) == null) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_POZA_ID));
        }
        return EventoPoza.crear(incomingUpdatedAt, id, change.uuid(F_POZA_ID), tipo,
                fecha == null ? LocalDate.now() : fecha, change.jsonMap(F_DETALLES));
    }

    @Override
    protected void overwrite(EventoPoza existing, long incomingUpdatedAt, SyncChange change) {
        existing.aplicarDesde(incomingUpdatedAt, change.uuid(F_POZA_ID), change.string(F_TIPO_EVENTO),
                change.date(F_FECHA_EVENTO), change.jsonMap(F_DETALLES));
    }

    @Override
    protected SyncRef snapshot(EventoPoza entity) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put(F_POZA_ID, entity.getPozaId());
        payload.put(F_TIPO_EVENTO, entity.getTipoEvento());
        payload.put(F_FECHA_EVENTO, entity.getFechaEvento());
        payload.put(F_DETALLES, entity.getDetalles());
        return new SyncRef(entity(), entity.getId().toString(), entity.getUpdatedAt(),
                entity.isDeleted(), payload);
    }
}
