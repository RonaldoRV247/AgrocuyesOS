# AgrocuyesOS

Sistema multiplataforma (móvil + web) para **gestión agrícola y crianza de
cuyes** en zonas con conectividad intermitente. Offline-first por diseño: el
dispositivo crea los datos con su propia identidad y el servidor reconcilia
lotes. Preparado para ingesta de datos vía IA mediante atributos dinámicos en
JSONB y catálogos definidos por el usuario (no enums).

## Stack

Spring Boot 3.5 · Java 21 · PostgreSQL 13+ (JSONB, GIN, FK diferidas) · Flyway ·
Clean Architecture.

## Documentación

Toda la documentación vive en [`docs/`](docs/README.md):

| | |
|---|---|
| [01 · Arquitectura](docs/01-arquitectura.md) | Capas, regla de dependencia, cómo correr |
| [02 · Modelo de datos](docs/02-modelo-de-datos.md) | Entidades, catálogo dinámico, JSONB, índices |
| [03 · Sincronización](docs/03-sincronizacion.md) | Last Write Wins, tombstones, concurrencia, reloj |
| [04 · API](docs/04-api.md) | Contrato del endpoint de sync y sus estados |
| [05 · Seguridad](docs/05-seguridad.md) | Google OAuth2 → JWT (diseño, aún **sin implementar**) |
| [06 · Decisiones](docs/06-decisiones.md) | Once decisiones con alternativa descartada y motivo |
| [07 · Roadmap](docs/07-roadmap.md) | Hecho, Fase 1–4 y deuda técnica |

## Estructura del repo

```
backend/     API Spring Boot (nucleo de sync implementado y probado)
frontend/    Clientes móvil/web (aún sin código)
docs/        Documentación de arquitectura y decisiones
```

## Estado

| | |
|---|---|
| Push de cambios + arbitraje LWW + JSONB + Flyway | **Implementado**: 13/13 tests (10 de arbitraje LWW, 3 sobre PostgreSQL real con Testcontainers) |
| Pull delta y autenticación | Diseñados, pendientes |
| Frontend | Pendiente |

⚠️ El endpoint de sincronización **no está autenticado** todavía y el `device_id`
es autodeclarado: no exponer a producción hasta cerrar el módulo de seguridad.

## Arrancar el backend

```bash
docker run -d --name agrocuyes-pg -e POSTGRES_USER=agrocuyes -e POSTGRES_PASSWORD=agrocuyes \
  -e POSTGRES_DB=agrocuyes -p 5432:5432 postgres:16-alpine

cd backend && mvn spring-boot:run     # Flyway aplica V1__sync_core.sql al arrancar
```

Pruebas (requiere Maven 3.9+/JDK 21, o el comando Docker de
[docs/01](docs/01-arquitectura.md)):

```bash
cd backend && mvn test
```
