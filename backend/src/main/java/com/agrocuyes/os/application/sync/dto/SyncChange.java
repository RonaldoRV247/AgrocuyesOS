package com.agrocuyes.os.application.sync.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Un cambio individual tal como lo envia el dispositivo offline.
 * `updated_at` es epoch-millis UTC en el reloj del dispositivo: es UNICO dato
 * que participa en el arbitraje LWW.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public record SyncChange(
        String entity,
        String id,
        String op,
        Long updatedAt,
        Map<String, Object> payload) {

    public static final String OP_UPSERT = "upsert";
    public static final String OP_DELETE = "delete";

    public boolean isDelete() {
        return OP_DELETE.equalsIgnoreCase(op);
    }

    public Map<String, Object> payloadOrEmpty() {
        return payload == null ? new LinkedHashMap<>() : payload;
    }

    public UUID idAsUuid() {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("missing id");
        }
        return UUID.fromString(id);
    }

    public long updatedAtOrThrow() {
        if (updatedAt == null || updatedAt <= 0) {
            throw new IllegalArgumentException("updated_at must be a positive epoch-millis");
        }
        return updatedAt;
    }

    public UUID uuid(String key) {
        Object value = payloadOrEmpty().get(key);
        if (value == null) {
            return null;
        }
        return value instanceof UUID uuid ? uuid : UUID.fromString(String.valueOf(value));
    }

    public String string(String key) {
        Object value = payloadOrEmpty().get(key);
        return value == null ? null : String.valueOf(value);
    }

    public Integer integer(String key) {
        Object value = payloadOrEmpty().get(key);
        if (value == null) {
            return null;
        }
        return value instanceof Number n ? n.intValue() : Integer.parseInt(String.valueOf(value));
    }

    public Double doubleValue(String key) {
        Object value = payloadOrEmpty().get(key);
        if (value == null) {
            return null;
        }
        return value instanceof Number n ? n.doubleValue() : Double.parseDouble(String.valueOf(value));
    }

    public Boolean bool(String key) {
        Object value = payloadOrEmpty().get(key);
        if (value == null) {
            return null;
        }
        return value instanceof Boolean b ? b : Boolean.parseBoolean(String.valueOf(value));
    }

    public java.time.LocalDate date(String key) {
        Object value = payloadOrEmpty().get(key);
        if (value == null) {
            return null;
        }
        if (value instanceof java.time.LocalDate date) {
            return date;
        }
        return java.time.LocalDate.parse(String.valueOf(value));
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> jsonMap(String key) {
        Object value = payloadOrEmpty().get(key);
        if (value == null) {
            return new LinkedHashMap<>();
        }
        if (value instanceof Map<?, ?> map) {
            return new LinkedHashMap<>((Map<String, Object>) map);
        }
        throw new IllegalArgumentException("field '%s' must be a JSON object".formatted(key));
    }
}
