# 04 · API de sincronización

Base: `/api/v1/sync`. Contrato en **snake_case** (fijado por
`spring.jackson.property-naming-strategy`).

## POST /api/v1/sync/changes

El dispositivo sube su cola de cambios offline. `200 OK` con el veredicto LWW
cambio por cambio.

### Request

```jsonc
{
  "device_id": "device-celular-01",
  "changes": [
    {
      "entity": "registro_actividad",
      "id": "0b9c1f2e-6d3a-4c7b-9e11-2f5a8c3d7b64",   // UUIDv4 generado en el cliente
      "op": "upsert",                                  // | "delete"
      "updated_at": 1700000000000,                     // epoch-millis UTC del dispositivo
      "payload": {
        "terreno_id": "…",
        "plantilla_id": "…",
        "fecha_realizada": "2026-10-10",
        "metadata": { "insumo": "semilla_maiz", "kg_aplicados": 12 }
      }
    }
  ]
}
```

Validación: `device_id` y `changes` son obligatorios; `entity` no puede venir
vacía; `updated_at` debe ser un positivo. El `payload` se valida contra las
reglas de la entidad (ver tabla de claves abajo).

### Entities aceptadas y sus claves de payload

| `entity` | Claves de `payload` |
|---|---|
| `terreno` | `nombre`*, `owner_id`*, `area_m2`, `lat`, `lng` |
| `plantilla_proceso` | `nombre`*, `metadata`, `activo` |
| `registro_actividad` | `terreno_id`, `plantilla_id`, `fecha_realizada`*, `metadata` |
| `galpon` | `nombre`*, `owner_id`*, `capacidad_maxima` |
| `poza` | `galpon_id`*, `codigo`*, `hembras`, `machos`, `crias` |
| `evento_poza` | `poza_id`*, `tipo_evento`*, `fecha_evento`, `detalles` |

\* obligatorio en alta (`upsert` sobre id desconocido).

### Response

```jsonc
{
  "device_id": "device-celular-01",
  "server_timestamp": 1700000060000,   // para que el cliente mida su deriva de reloj
  "accepted": 1,
  "rejected": 0,
  "results": [
    {
      "entity": "registro_actividad",
      "id": "0b9c1f2e-…",
      "status": "APPLIED",
      "server_updated_at": 1700000000000,
      "server_deleted": false,
      "server_payload": { "terreno_id": "…", "metadata": { "insumo": "semilla_maiz" } }
    }
  ]
}
```

### Estados (`status`)

| Status | Significado | Qué debe hacer el cliente |
|---|---|---|
| `INSERTED` | Alta aceptada | Sacar de la cola |
| `APPLIED` | Ganó el payload y sobrescribió la fila | Sacar de la cola |
| `TOMBSTONED` | Borrado aceptado (la fila queda como marcador) | Sacar de la cola |
| `DUPLICATE` | `updated_at` igual al almacenado: reintento | Sacar de la cola (no duplica datos) |
| `STALE` | El dispositivo traía datos más viejos | **Descartar la copia local** y adoptar `server_payload` |
| `REJECTED_DELETED` | El registro está borrado en otro lado | Descartar el cambio local (borrado pegajoso) |
| `REJECTED` | No se persistió: payload inválido, clock skew o entidad no soportada | No reintentar igual: corregir el cambio o avisar |

`accepted` cuenta `INSERTED`, `APPLIED`, `TOMBSTONED` y `DUPLICATE`; todo lo
demás va a `rejected`.

### Errores a nivel de request

| Condición | HTTP |
|---|---|
| `device_id` o `changes` ausentes, o `entity` vacía | `400` (Bean Validation) |
| Error de persistencia en cualquier cambio | el lote entero aborta → `500`; el cliente reintenta la cola completa |
| Entidad no soportada | **no** es error HTTP: `200` con `status=REJECTED` |

## Pendiente de contrato

- `GET /api/v1/sync/changes?since=<watermark>&limit=…` (pull delta).
- Cabecera `Idempotency-Key` para reintentos a nivel de lote.
- Autenticación: `Authorization: Bearer <access_token>` (ver
  [05-seguridad.md](05-seguridad.md)).
