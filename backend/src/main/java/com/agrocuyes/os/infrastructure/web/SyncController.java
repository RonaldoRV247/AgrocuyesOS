package com.agrocuyes.os.infrastructure.web;

import com.agrocuyes.os.application.sync.dto.SyncRequestDto;
import com.agrocuyes.os.application.sync.dto.SyncResponseDto;
import com.agrocuyes.os.application.sync.service.SyncService;
import jakarta.validation.Valid;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Adapter HTTP del caso de uso de sincronizacion. Delgado a proposito: validar,
 * delegar y serializar.
 */
@RestController
@RequestMapping(value = "/api/v1/sync", produces = MediaType.APPLICATION_JSON_VALUE)
public class SyncController {

    private final SyncService syncService;

    public SyncController(SyncService syncService) {
        this.syncService = syncService;
    }

    /**
     * POST /api/v1/sync/changes
     * El dispositivo sube su cola de cambios offline y recibe el veredicto LWW
     * de cada uno (mas la version autoritativa cuando perdio).
     */
    @PostMapping(path = "/changes", consumes = MediaType.APPLICATION_JSON_VALUE)
    public SyncResponseDto pushChanges(@Valid @RequestBody SyncRequestDto request) {
        return syncService.pushChanges(request);
    }
}
