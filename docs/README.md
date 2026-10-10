# Documentación · AgrocuyesOS

Sistema multiplataforma (móvil + web) de gestión agrícola y crianza de cuyes,
diseñado para **zonas con conectividad intermitente** (offline-first) y
preparado para **ingesta de datos vía IA**.

## Índice

| Doc | Qué responde |
|---|---|
| [01-arquitectura.md](01-arquitectura.md) | Capas, regla de dependencia, mapa de paquetes, cómo correr el backend |
| [02-modelo-de-datos.md](02-modelo-de-datos.md) | Entidades, catálogo dinámico, JSONB, convenciones de columnas, índices |
| [03-sincronizacion.md](03-sincronizacion.md) | Protocolo offline-first: Last Write Wins, tombstones, concurrencia, reloj |
| [04-api.md](04-api.md) | Contrato del endpoint de sync: payloads, estados de resultado, errores |
| [05-seguridad.md](05-seguridad.md) | Diseño de autenticación Google OAuth2 → JWT (acceso corto / refresh perpetuo) |
| [06-decisiones.md](06-decisiones.md) | Decisiones de arquitectura con alternativa descartada y motivo |
| [07-roadmap.md](07-roadmap.md) | Qué está implementado y qué sigue, por fases |

## Estado del sistema (resumen honesto)

| Componente | Estado |
|---|---|
| Núcleo de sincronización (push + LWW + JSONB + Flyway) | **Implementado y probado**: 13/13 tests (10 de arbitraje LWW sin BD, 3 de rebanada vertical sobre PostgreSQL real con Testcontainers) |
| Pull delta (el servidor devuelve cambios al dispositivo) | Diseñado, **no implementado** |
| Autenticación Google OAuth2 → JWT | Diseñado en [05-seguridad.md](05-seguridad.md), **no implementado** |
| Frontend (móvil y web) | Sin código todavía (solo `frontend/README.md` con las reglas que ya le aplican) |

## Reglas de diseño que no se negocian

1. **UUIDv4 generado en el cliente** como PK de toda entidad sincronizable; ese
   UUID es además la clave de idempotencia del sync.
2. **Catálogos dinámicos, nunca enums**: un tipo nuevo de actividad o evento es
   un `INSERT`, no un deploy.
3. **`JSONB` para lo variable**: atributos nuevos (manuales o de IA) no requieren
   `ALTER TABLE`.
4. **Last Write Wins sobre `updated_at` en epoch-millis** (BIGINT), no TIMESTAMP.
5. **Regla de dependencia hacia adentro**: HTTP, JPA y SQL viven solo en
   `infrastructure/`.
