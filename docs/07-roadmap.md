# 07 · Roadmap

## Hecho

- Estructura Clean Architecture del backend (domain / application / infrastructure).
- 7 entidades de los dos cores (tareas y crianza) con base común sincronizable.
- Endpoint de push `POST /api/v1/sync/changes` con arbitraje LWW, tombstones,
  idempotencia y bloqueo pesimista.
- Mapeo JSONB verificado contra PostgreSQL real; `V1__sync_core.sql` con Flyway
  (índices GIN incluidos) y `ddl-auto: validate`.
- 13 tests (10 de arbitraje LWW, 3 de rebanada vertical con Testcontainers).

## Fase 1 · cerrar lo que hace falta para que el sync sea usable

- [ ] **Pull delta**: `GET /api/v1/sync/changes?since=<watermark>&limit=…`
      apoyado en los índices `*_updated_at`. Sin esto el dispositivo nunca
      converge: solo empuja.
- [ ] **Autenticación Google OAuth2 → JWT** ([05-seguridad.md](05-seguridad.md)):
      access corto, refresh largo con rotación y detección de reuso, `device_id`
      atado al token, `owner_id` derivado del JWT. Bloqueante antes de exponer
      nada.
- [ ] **`Idempotency-Key`** por request, para reintentos a nivel de lote.
- [ ] **Maven Wrapper** (`mvnw`) y CI que corra `mvn test` con Docker disponible.
- [ ] **Limpieza de huérfanos**: registros cuyo `terreno`/`poza` fue borrado.

## Fase 2 · catálogo dinámico completo

- [ ] `ProcesoPersonalizado` como catálogo maestro de tipos (tareas y eventos
      crianza comparten un solo registro de tipos con `dominio = 'tarea'|'crianza'`).
- [ ] **Formulario versionado por tipo**: las claves que admite `metadata` se
      declaran como datos (`field_defs jsonb`) y se validan al sincronizar, para
      que la libertad del JSONB no derive en basura intratable.
- [ ] Validación por `CHECK (jsonb_typeof(metadata) = 'object')` o equivalente.

## Fase 3 · clientes

- [ ] Móvil: cola de cambios persistida (SQLite/Drift, o Realm), reintentos con
      backoff, medición de deriva de reloj contra `server_timestamp`, y reglas de
      UI para `STALE` / `REJECTED_DELETED` (hay que decirle al usuario por qué su
      cambio no se guardó).
- [ ] Web: misma API, sesión con access token corto.
- [ ] Decisión abierta: framework del cliente (Flutter / React Native / web + PWA).
      No está tomada; condiciona el formato de la cola local.

## Fase 4 · preparado para IA

- [ ] Ingesta por lotes desde modelos (visión de plagas, OCR de libretas,
      pesos predichos) escribiendo en `metadata`/`detalles` con clave de
      procedencia (`fuente`, `modelo`, `confianza`).
- [ ] Vista/vista materializada que desate las claves JSONB más consultadas para
      reportes sin escanear JSON.
- [ ] Auditoría de qué escribió un agente vs. qué escribió una persona.

## Deuda técnica conocida

- `SyncChange` devuelve `null` ante payload ausente en vez de fallar: los
  handlers validan campo por campo, que funciona pero dispersa las reglas.
- No hay tests de concurrencia real (dos dispositivos sobre el mismo registro en
  paralelo); hoy se confía en el `FOR UPDATE` sin comprobarlo.
- `accepted`/`rejected` tratan `DUPLICATE` como aceptado; si algún día importa
  el detalle, conviene un contador por status.
