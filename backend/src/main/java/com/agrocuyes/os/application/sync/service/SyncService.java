package com.agrocuyes.os.application.sync.service;

import com.agrocuyes.os.application.sync.dto.SyncChange;
import com.agrocuyes.os.application.sync.dto.SyncRequestDto;
import com.agrocuyes.os.application.sync.dto.SyncResponseDto;
import com.agrocuyes.os.application.sync.dto.SyncResultDto;
import com.agrocuyes.os.application.sync.dto.SyncStatus;
import com.agrocuyes.os.application.sync.port.MergeOutcome;
import com.agrocuyes.os.application.sync.port.SyncHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.LongSupplier;

/**
 * Orquestador del endpoint de sincronizacion.
 *
 * Responsabilidades (y solo estas): enrutar cada cambio al handler de su
 * entidad, rodear el lote de UNA transaccion, traducir el MergeOutcome sellado
 * al DTO del contrato publico y reportar el reloj del servidor para que el
 * dispositivo pueda corregir su deriva horaria.
 *
 * No conoce JPA, ni Postgres, ni HTTP: todo eso entra por los puertos
 * SyncHandler / SyncRepository (Clean Architecture, dependencia hacia adentro).
 */
@Service
public class SyncService {

    private static final Logger log = LoggerFactory.getLogger(SyncService.class);

    private final Map<String, SyncHandler<?>> handlersByEntity;
    private final LongSupplier clock;

    public SyncService(List<SyncHandler<?>> handlers, LongSupplier syncClock) {
        this.clock = syncClock;
        this.handlersByEntity = new HashMap<>();
        for (SyncHandler<?> handler : handlers) {
            SyncHandler<?> previous = this.handlersByEntity.putIfAbsent(handler.entity(), handler);
            if (previous != null) {
                throw new IllegalStateException("Duplicated sync handler for entity '%s'".formatted(handler.entity()));
            }
        }
        log.info("Sync handlers registered: {}", this.handlersByEntity.keySet());
    }

    /**
     * Una transaccion por lote: si algo falla de forma inesperada se descarta el
     * batch completo y el dispositivo reintenta su cola entera. Los fallos por
     * invariante (INVALID_PAYLOAD) NO abortan: se reportan cambio por cambio.
     */
    @Transactional
    public SyncResponseDto pushChanges(SyncRequestDto request) {
        List<SyncResultDto> results = new ArrayList<>(request.changes().size());
        int accepted = 0;
        int rejected = 0;

        for (SyncChange change : request.changes()) {
            SyncResultDto result = applyOne(change);
            results.add(result);
            switch (result.status()) {
                case INSERTED, APPLIED, TOMBSTONED, DUPLICATE -> accepted++;
                default -> rejected++;
            }
        }

        return new SyncResponseDto(request.deviceId(), clock.getAsLong(), accepted, rejected, results);
    }

    private SyncResultDto applyOne(SyncChange change) {
        SyncHandler<?> handler = handlersByEntity.get(normalize(change.entity()));
        if (handler == null) {
            return SyncResultDto.of(change.entity(), change.id(), SyncStatus.REJECTED,
                    "unsupported entity '%s'".formatted(change.entity()));
        }
        // Los fallos de validacion los devuelve el handler como REJECTED (no toca la BD).
        // Un error de persistencia NO se atrapa: PostgreSQL aborta la transaccion
        // en el primer error SQL, asi que fingir que el resto del lote sigue vivo
        // solo produce un UnexpectedRollbackException incomprensible al commit.
        return toResult(handler.apply(change));
    }

    private SyncResultDto toResult(MergeOutcome outcome) {
        return switch (outcome) {
            case MergeOutcome.Inserted ins -> SyncResultDto.of(ins.ref(), SyncStatus.INSERTED);
            case MergeOutcome.Applied applied -> SyncResultDto.of(applied.ref(), SyncStatus.APPLIED);
            case MergeOutcome.Tombstoned tomb -> SyncResultDto.of(tomb.ref(), SyncStatus.TOMBSTONED);
            case MergeOutcome.Duplicate dup -> SyncResultDto.of(dup.ref(), SyncStatus.DUPLICATE);
            case MergeOutcome.Stale stale -> SyncResultDto.of(stale.serverState(), SyncStatus.STALE);
            case MergeOutcome.RejectedDeleted rej ->
                    SyncResultDto.of(rej.serverState(), SyncStatus.REJECTED_DELETED);
            case MergeOutcome.Rejected rej -> {
                Map<String, Object> details = rej.details();
                yield SyncResultDto.of(
                        String.valueOf(details.get("entity")),
                        String.valueOf(details.get("id")),
                        SyncStatus.REJECTED,
                        "%s: %s".formatted(rej.reason(), details.get("message")));
            }
        };
    }

    private String normalize(String entity) {
        return entity == null ? "" : entity.trim().toLowerCase();
    }
}
