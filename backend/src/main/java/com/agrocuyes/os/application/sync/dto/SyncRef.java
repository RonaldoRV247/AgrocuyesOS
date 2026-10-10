package com.agrocuyes.os.application.sync.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.Map;

/**
 * Estado autoritativo del servidor para un registro, devuelto en los casos de
 * conflicto (STALE / REJECTED_DELETED) para que el dispositivo abandone su
 * version local y adopte la del server sin necesidad de un pull adicional.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public record SyncRef(
        String entity,
        String id,
        long updatedAt,
        boolean deleted,
        Map<String, Object> payload) {
}
