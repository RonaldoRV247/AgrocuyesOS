package com.agrocuyes.os.application.sync.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

/**
 * Payload de POST /api/v1/sync/changes.
 * Un dispositivo offline sube su cola de cambios completa en un solo request;
 * el server responde con el veredicto LWW cambio por cambio.
 */
public record SyncRequestDto(

        @NotBlank(message = "device_id is required for sync auditing")
        String deviceId,

        @NotEmpty(message = "changes must not be empty")
        @Valid
        List<SyncChange> changes) {

    @AssertTrue(message = "every change must declare an entity")
    public boolean allChangesHaveEntity() {
        return changes == null || changes.stream().allMatch(c -> c.entity() != null && !c.entity().isBlank());
    }
}
