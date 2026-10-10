# 01 · Arquitectura

Spring Boot 3.5 · Java 21 · PostgreSQL 13+ · Clean Architecture.

## Capas y regla de dependencia

```
infrastructure/  ──►  application/  ──►  domain/
   (adapters)          (casos de uso)     (entidades + reglas)
```

Nada apunta hacia afuera. `domain/` no conoce JPA salvo anotaciones de mapeo;
`application/` no conoce HTTP, SQL ni Spring Data; lo único que se permite ahí es
anotación de bean y `@Value` de configuración.

## Mapa de paquetes (`backend/src/main/java/com/agrocuyes/os`)

```
AgrocuyesApplication.java

domain/
  shared/SyncableEntity.java        @MappedSuperclass: PK asignada, created_at/updated_at
                                    (bigint millis), tombstone, @Version, acceptsOverwrite(),
                                    touch(), softDelete()
  tasks/                            Core dinámico de tareas
    Terreno.java                    lote de cultivo (GPS, área)
    PlantillaProceso.java           catálogo dinámico (Riego, Siembra...) + metadata JSONB
    RegistroActividad.java          la transacción: terreno + plantilla + fecha + metadata JSONB
  cria/                             Core crianza (cuyes)
    Galpon.java                     instalación física
    Poza.java                       corral con lote de cuyes
    EventoPoza.java                 transacción: tipo_evento TEXT + detalles JSONB

application/sync/
  dto/                              contrato público del API
    SyncChange.java                 entity, id, op, updated_at, payload
    SyncRequestDto / SyncResponseDto / SyncResultDto / SyncRef / SyncStatus
  port/                             interfaces que infraestructura implementa
    SyncHandler.java                apply(change) -> MergeOutcome
    SyncRepository.java             loadForUpdate / insert / update
    MergeOutcome.java               sealed: Inserted|Applied|Stale|Duplicate|
                                    Tombstoned|RejectedDeleted|Rejected
    EntityTypes.java                claves de enrutamiento (strings, no enums de dominio)
  service/
    LwwSyncHandler.java             LA regla LWW, escrita una sola vez
    SyncService.java                enruta por entidad + una transacción por lote
  handler/                          un handler por entidad (mapeo payload <-> entidad)
    RegistroActividadSyncHandler, TerrenoSyncHandler, PlantillaProcesoSyncHandler,
    GalponSyncHandler, PozaSyncHandler, EventoPozaSyncHandler

infrastructure/
  persistence/JpaSyncRepository.java  genérico por tipo: SELECT...FOR UPDATE, persist, merge
  web/SyncController.java             POST /api/v1/sync/changes
  config/SyncConfig.java              syncClock + un SyncRepository por entidad
```

Recursos: `application.yml` y `db/migration/V1__sync_core.sql` (el DDL es
propiedad de Flyway; Hibernate solo valida con `ddl-auto: validate`).

## Pruebas

| Test | Qué garantiza |
|---|---|
| `SyncServiceLwwTest` (10 casos) | Arbitraje LWW puro: insert, overwrite, stale, duplicate, tombstone, tombstone pegajoso, clock skew, payload inválido, entidad desconocida, reloj del server en la respuesta. Sin Spring ni BD. |
| `SyncJsonbIntegrationTest` (3 casos) | Rebanada vertical real sobre PostgreSQL efímero: HTTP → service → handler → JPA/JSONB → Flyway V1. Verifica que el mapeo jsonb coincide con el DDL, que las FK diferidas aceptan un lote con el hijo antes que el padre, y que los operadores `@>` / `->>` funcionan sobre lo sincronizado. |

## Cómo correr

El proyecto no trae Maven en el repo (`.mvnw` pendiente, ver roadmap). Con Docker:

```bash
# tests (unitarios + integración con Postgres efímero)
docker run --rm --network host \
  -v "$PWD":/src -v agrocuyes-m2:/root/.m2 -v /var/run/docker.sock:/var/run/docker.sock \
  -e DOCKER_HOST=unix:///var/run/docker.sock -e TESTCONTAINERS_RYUK_DISABLED=true \
  -w /src -u 0 maven:3.9-eclipse-temurin-21 mvn -B test

# app contra Postgres local
docker run -d --name agrocuyes-pg -e POSTGRES_USER=agrocuyes -e POSTGRES_PASSWORD=agrocuyes \
  -e POSTGRES_DB=agrocuyes -p 5432:5432 postgres:16-alpine
mvn spring-boot:run        # Flyway aplica V1 al arrancar
```

Con Maven local: `mvn test` / `mvn spring-boot:run` desde `backend/`.

## Configuración

`application.yml` lee todo por variable de entorno; los valores por defecto son
de desarrollo local y **no** deben usarse en producción:

| Clave | Env | Default | Nota |
|---|---|---|---|
| `spring.datasource.url` | `AGROCUYES_DB_URL` | jdbc:postgresql://localhost:5432/agrocuyes | |
| `spring.datasource.username` | `AGROCUYES_DB_USER` | `agrocuyes` | solo dev |
| `spring.datasource.password` | `AGROCUYES_DB_PASSWORD` | `agrocuyes` | solo dev |
| `server.port` | `PORT` | 8080 | |
| `agrocuyes.sync.max-clock-skew-ms` | — | 300000 | tolerancia de reloj de campo |

`spring.jackson.property-naming-strategy: SNAKE_CASE` fija el contrato del API
(`device_id`, `updated_at`, `server_payload`).
