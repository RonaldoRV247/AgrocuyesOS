package com.agrocuyes.os.application.sync.handler;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRef;
import com.agrocuyes.os.application.sync.port.EntityTypes;
import com.agrocuyes.os.application.sync.port.SyncRepository;
import com.agrocuyes.os.application.sync.service.LwwSyncHandler;
import com.agrocuyes.os.domain.cria.Poza;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.LongSupplier;

@Component
public class PozaSyncHandler extends LwwSyncHandler<Poza> {

    public static final String F_GALPON_ID = "galpon_id";
    public static final String F_CODIGO = "codigo";
    public static final String F_HEMBRAS = "hembras";
    public static final String F_MACHOS = "machos";
    public static final String F_CRIAS = "crias";

    public PozaSyncHandler(SyncRepository<Poza> repository, LongSupplier syncClock) {
        super(repository, syncClock);
    }

    @Override
    public String entity() {
        return EntityTypes.POZA;
    }

    @Override
    protected Poza create(UUID id, long incomingUpdatedAt, SyncChange change) {
        String codigo = change.string(F_CODIGO);
        if (codigo == null || codigo.isBlank()) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_CODIGO));
        }
        if (change.uuid(F_GALPON_ID) == null) {
            throw new IllegalArgumentException("'%s' is required".formatted(F_GALPON_ID));
        }
        Poza poza = Poza.crear(incomingUpdatedAt, id, change.uuid(F_GALPON_ID), codigo);
        poza.setHembras(change.integer(F_HEMBRAS));
        poza.setMachos(change.integer(F_MACHOS));
        poza.setCrias(change.integer(F_CRIAS));
        return poza;
    }

    @Override
    protected void overwrite(Poza existing, long incomingUpdatedAt, SyncChange change) {
        existing.aplicarDesde(incomingUpdatedAt, change.uuid(F_GALPON_ID), change.string(F_CODIGO),
                change.integer(F_HEMBRAS), change.integer(F_MACHOS), change.integer(F_CRIAS));
    }

    @Override
    protected SyncRef snapshot(Poza entity) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put(F_GALPON_ID, entity.getGalponId());
        payload.put(F_CODIGO, entity.getCodigo());
        payload.put(F_HEMBRAS, entity.getHembras());
        payload.put(F_MACHOS, entity.getMachos());
        payload.put(F_CRIAS, entity.getCrias());
        return new SyncRef(entity(), entity.getId().toString(), entity.getUpdatedAt(),
                entity.isDeleted(), payload);
    }
}
