# 03 · Sincronización (Offline-First + Last Write Wins)

El dispositivo es el **origen de verdad de sus altas**: crea la fila con su
propio UUIDv4 y su `updated_at` local, la encola, y sube el lote cuando tiene
señal. El servidor **reconcilia lotes**, no operaciones unitarias.

## La regla LWW, escrita una sola vez

Implementación: `application/sync/service/LwwSyncHandler<E>.apply(change)`.
Cada entidad aporta solo 3 hooks de mapeo (`create`, `overwrite`, `snapshot`).

```
0. validar id/updated_at y ventana de reloj   -> REJECTED
1. id inexistente + op=upsert                 -> INSERT
   id inexistente + op=delete                 -> TOMBSTONED (sin efecto, no es error)
2. updated_at actual >= entrante
     ==  -> DUPLICATE   (reintento de la misma cola: no-op idempotente)
     >   -> STALE       (el dispositivo traía datos viejos)
3. tombstone vigente                          -> REJECTED_DELETED
4. op=delete                                  -> TOMBSTONED (softDelete)
5. resto                                      -> APPLIED (sobrescritura completa)
```

Comparación: `SyncableEntity.acceptsOverwrite(incoming) = incoming > updatedAt`,
y `touch(new)` rechaza escribir un timestamp menor o igual (defensa de
invariante, no solo de convención).

### El servidor devuelve su versión cuando gana

En `STALE` y `REJECTED_DELETED` la respuesta incluye `server_updated_at`,
`server_deleted` y `server_payload`. Así el dispositivo abandona su copia local
sin necesidad de un pull adicional. Sin esto, un conflicto deja el cliente
convergiendo a ciegas.

### Borrados pegajosos (trade-off deliberado)

Un `upsert` con timestamp **mayor** sobre un tombstone **no resucita** la fila:
`REJECTED_DELETED`. Evita que una edición vieja atrapada en la cola de otro
dispositivo reviva algo que alguien borró a propósito. El costo: para "revivir"
un registro hay que crear uno nuevo con otro UUID. Si el negocio necesita
restauración explícita, se agrega una operación `restore` dedicada (ver roadmap),
no se relaja la regla.

### LWW es de campo, no de reloj de pared

`updated_at` lo pone el dispositivo. Dos dispositivos con reloj desincronizado
producen el mismo resultado observable para el usuario, pero **un reloj
adelantado ganaría todos los conflictos para siempre**. Por eso el servidor
rechaza cualquier `updated_at` que exceda su hora + `max-clock-skew-ms`, y
devuelve `server_timestamp` en cada respuesta para que el cliente mida su deriva.

## Concurrencia y transacción

- **Bloqueo pesimista por PK**: `loadForUpdate` = `SELECT … FOR UPDATE`
  (`LockModeType.PESSIMISTIC_WRITE`). Dos lotes que suben el mismo registro se
  serializan y el read-modify-write del LWW no se pisa.
- **Una transacción por lote** (`SyncService.pushChanges`).
- **Fallos de validación: cambio por cambio.** El handler devuelve `REJECTED`
  sin tocar la BD, así que una fila corrupta en la cola no impide sincronizar
  las demás.
- **Errores de persistencia: abortan el lote.** No se atrapan a propósito:
  PostgreSQL aborta la transacción en el primer error SQL, y simular que el
  resto sobrevive solo produce un `UnexpectedRollbackException` incomprensible
  al commit. El dispositivo reintenta su cola entera.
- **Orden libre dentro del lote**: gracias a las FK diferidas, actividad →
  plantilla → terreno en ese orden funciona (caso cubierto por
  `SyncJsonbIntegrationTest`).

## Idempotencia

Tres mecanismos superpuestos:

1. PK asignada: reenviar el mismo cambio cae en `DUPLICATE`.
2. `updated_at` igual = no-op; no se duplica información ni se mueve el reloj.
3. `uq_registro_client_uuid`: si el cliente reusa un `client_uuid`, la BD lo
   frena aunque el arbitraje dijera otra cosa.

Falta la capa de lote (`Idempotency-Key` por request): pendiente en el roadmap.

## Qué todavía NO hace el servidor

| Brecha | Consecuencia hoy |
|---|---|
| **Pull delta** (`GET /sync/changes?since=<watermark>`) | El dispositivo solo puede empujar; no recupera cambios hechos en otros dispositivos ni en la web. Los índices `*_updated_at` ya están listos. |
| **Autenticación / autorización** | `/api/v1/sync/changes` está abierto y `device_id` es autodeclarado. No exponer a producción hasta cerrar [05-seguridad.md](05-seguridad.md). |
| **Merge de JSONB a nivel de clave** | `APPLIED` reemplaza el `metadata` completo. Dos ediciones parciales de la misma metadata no se fusionan: gana la más nueva en bloque. Es LWW puro, y está bien así, pero conviene que el cliente sepa que su payload reemplaza, no parchea. |
| **Conflicto en claves foráneas** | Un `registro_actividad` que apunta a un `terreno` borrado en otro lado queda huérfano hasta que el lote de limpieza exista. |
