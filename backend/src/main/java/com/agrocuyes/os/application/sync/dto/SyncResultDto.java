package com.agrocuyes.os.application.sync.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Como quedo UN cambio despues del arbitraje.
 *
 * - INSERTED / APPLIED      : el server acepto el estado del dispositivo.
 * - TOMBSTONED              : borrado aceptado (la fila sigue viva como marcador).
 * - STALE                   : el dispositivo traia datos viejos; server_payload manda la version vigente.
 * - DUPLICATE               : mismo updated_at; los reintentos no duplican informacion.
 * - REJECTED_DELETED        : el registro fue borrado en otro lado; no se reactiva.
 * - REJECTED                : no se persistio (payload invalido o entidad desconocida).
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record SyncResultDto(
        String entity,
        String id,
        SyncStatus status,
        Long serverUpdatedAt,
        Boolean serverDeleted,
        java.util.Map<String, Object> serverPayload,
        String error) {

    public static SyncResultDto of(SyncRef ref, SyncStatus status) {
        return new SyncResultDto(ref.entity(), ref.id(), status,
                ref.updatedAt(), ref.deleted(), ref.payload(), null);
    }

    public static SyncResultDto of(String entity, String id, SyncStatus status, String error) {
        return new SyncResultDto(entity, id, status, null, null, null, error);
    }
}
