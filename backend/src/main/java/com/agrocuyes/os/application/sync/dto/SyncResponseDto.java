package com.agrocuyes.os.application.sync.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record SyncResponseDto(
        String deviceId,
        long serverTimestamp,
        int accepted,
        int rejected,
        List<SyncResultDto> results) {
}
