package com.agrocuyes.os.application.sync.dto;

public enum SyncStatus {
    INSERTED,
    APPLIED,
    TOMBSTONED,
    STALE,
    DUPLICATE,
    REJECTED_DELETED,
    REJECTED
}
