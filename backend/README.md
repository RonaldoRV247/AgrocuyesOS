# AgrocuyesOS · backend

Núcleo de sincronización Offline-First (Spring Boot 3.5 · Java 21 · PostgreSQL).

La documentación del proyecto está en [`../docs`](../docs/README.md); este README
es solo el arranque del módulo.

| Quiero saber… | Doc |
|---|---|
| Capas y mapa de paquetes | [docs/01-arquitectura.md](../docs/01-arquitectura.md) |
| Entidades, catálogo dinámico, JSONB, índices | [docs/02-modelo-de-datos.md](../docs/02-modelo-de-datos.md) |
| Regla Last Write Wins, tombstones, concurrencia | [docs/03-sincronizacion.md](../docs/03-sincronizacion.md) |
| Contrato del endpoint y sus estados | [docs/04-api.md](../docs/04-api.md) |
| Autenticación (diseño, aún sin implementar) | [docs/05-seguridad.md](../docs/05-seguridad.md) |
| Por qué se decidió cada cosa | [docs/06-decisiones.md](../docs/06-decisiones.md) |
| Qué sigue | [docs/07-roadmap.md](../docs/07-roadmap.md) |

## Dónde vive lo importante

- `domain/shared/SyncableEntity.java` → base común: PK asignada, `updated_at` en
  epoch-millis, tombstone, regla de sobrescritura.
- `domain/tasks/RegistroActividad.java` → entidad con `metadata` **jsonb**.
- `application/sync/service/LwwSyncHandler.java` → **la regla LWW, una sola vez**.
- `application/sync/service/SyncService.java` → enrutado por entidad + transacción
  por lote.
- `infrastructure/persistence/JpaSyncRepository.java` → `SELECT … FOR UPDATE`,
  `persist` / `merge` (por eso el puerto separa `insert` de `update`).
- `src/main/resources/db/migration/V1__sync_core.sql` → DDL, índices GIN y FK
  diferidas. Flyway es el dueño del esquema (`ddl-auto: validate`).

## Correr

```bash
docker run -d --name agrocuyes-pg -e POSTGRES_USER=agrocuyes -e POSTGRES_PASSWORD=agrocuyes \
  -e POSTGRES_DB=agrocuyes -p 5432:5432 postgres:16-alpine
mvn spring-boot:run                 # requiere Maven 3.9+ / JDK 21
```

```bash
mvn test                            # 10 tests de LWW + 3 de rebanada vertical (Testcontainers)
```

Sin Maven local (Docker); necesita el socket montado para Testcontainers:

```bash
docker run --rm --network host \
  -v "$PWD":/src -v agrocuyes-m2:/root/.m2 -v /var/run/docker.sock:/var/run/docker.sock \
  -e DOCKER_HOST=unix:///var/run/docker.sock -e TESTCONTAINERS_RYUK_DISABLED=true \
  -w /src -u 0 maven:3.9-eclipse-temurin-21 mvn -B test
```

⚠️ `POST /api/v1/sync/changes` **aún no está autenticado** y `device_id` es
autodeclarado: no exponer a producción antes de cerrar
[docs/05-seguridad.md](../docs/05-seguridad.md).
