# 02 · Modelo de datos

PostgreSQL 13+ (`gen_random_uuid()` es nativo desde esa versión). DDL de
referencia: `backend/src/main/resources/db/migration/V1__sync_core.sql`.

## Convenciones que aplican a TODAS las entidades

| Convención | Por qué |
|---|---|
| `id uuid PRIMARY KEY` **asignado por el cliente** | Offline-first: la fila nace en el dispositivo. El `DEFAULT gen_random_uuid()` del DDL solo cubre altas nacidas en el server (web/seeds). |
| `created_at bigint NOT NULL`, `updated_at bigint NOT NULL` | Epoch-millis **UTC**. No `TIMESTAMPTZ`: LWW necesita comparar en la misma unidad y formato que usa el dispositivo, sin conversión de zona. |
| `deleted boolean`, `deleted_at bigint` | Tombstone. Borrar es un **estado replicable**, no la ausencia de la fila: si no se propaga, el registro resucita en el otro dispositivo. |
| `version bigint NOT NULL` | Contador de ciclo de vida de JPA. **No** participa en la resolución de conflictos. Ver [06-decisiones.md](06-decisiones.md) (D2). |
| `metadata` / `detalles jsonb` | Atributos variables sin `ALTER TABLE`. |
| FK `DEFERRABLE INITIALLY DEFERRED` | Un lote de sync puede traer al hijo antes que al padre; se valida al commit. |
| Sin `@ManyToOne` en el dominio | Relaciones como `<otra>_id uuid`: el padre puede estar pendiente de sincronizar. |

## Core dinámico de tareas

**`terreno`** — lote de cultivo.
`nombre`, `area_m2`, `lat`, `lng` (GPS capturado en campo), `owner_id`.

**`plantilla_proceso`** — catálogo dinámico de actividades (Riego, Siembra,
Fertilización…). No existe ningún enum de tipo de actividad: el usuario define
tipos nuevos en tiempo de ejecución.
`nombre`, `metadata jsonb` (pasos, herramientas, insumos), `activo`.

**`registro_actividad`** — la transacción central.
`client_uuid` (= id, `UNIQUE`: clave de idempotencia del sync), `terreno_id`,
`plantilla_id`, `fecha_realizada date`, `metadata jsonb`.

```jsonc
// metadata de un registro de tipo "Siembra"
{ "insumo": "semilla_maiz", "kg_aplicados": 12, "humedad_pct": 18 }
// metadata de un registro de tipo "Fertilización" (claves distintas, misma columna)
{ "insumo": "compost", "saco": "S-11", "lote_ai": "IA-2026-10" }
```

## Core crianza (cuyes)

**`galpon`** — instalación física: `nombre`, `capacidad_maxima`, `owner_id`.

**`poza`** — corral dentro de un galpón: `galpon_id`, `codigo`, `hembras`,
`machos`, `crias`.

**`evento_poza`** — la transacción del core de crianza (Monta, Parto, Destete,
Mortalidad…). `tipo_evento` es **TEXT libre** que referencia el catálogo
dinámico: agregar "Vacunación" o un tipo inventado por un modelo de IA es un
dato, no un deploy.

```jsonc
// detalles por tipo de evento: cambia la forma del dato, no el esquema
{ "macho_id": "…", "peso_macho_g": 980 }                        // Monta
{ "numero_crias": 3, "peso_total_g": 240, "muerte_hembra": false } // Parto
```

## Índices de `V1`

| Índice | Tipo | Uso |
|---|---|---|
| `*_updated_at` (registro, evento, terreno, poza) | btree | Pull delta: traer lo cambiado desde el watermark del dispositivo |
| `idx_registro_terreno` | btree parcial `WHERE deleted = false` | Pantalla de actividades de un lote por fecha |
| `idx_evento_poza_por_tipo` | btree parcial | Historial de una poza filtrado por tipo de evento |
| `idx_poza_por_galpon` | btree parcial | Pozas de un galpón |
| `idx_registro_metadata_gin`, `idx_evento_detalles_gin`, `idx_plantilla_metadata_gin` | **GIN `jsonb_path_ops`** | Búsqueda dentro del JSONB con `@>` (reportes dinámicos e ingesta IA) |

## Nota para la ingesta IA

La columna JSONB es el punto de entrada de datos variables: un pipeline de IA
puede emitir claves nuevas (detección de plagas estimada por visión, pesos
predichos, OCR de una libreta de campo) **sin migración SQL**. Consecuencias a
mantener presentes:

- Escriba siempre JSON **plano y tipado** (string/number/boolean/array de
  escalares): las claves anidadas profundas complican las consultas `->>`.
- Toda clave en snake_case y sin ambigüedad de unidad (`kg_aplicados`,
  `peso_g`, `humedad_pct`).
- El índice GIN usa `jsonb_path_ops`: está optimizado para contención `@>`, no
  para `?|`/`?&`. Si aparecen consultas por clave-existencia masivas, evaluar un
  segundo índice `gin (metadata)`.
- Conviene un `CHECK (jsonb_typeof(metadata) = 'object')` o validación de
  payload por tipo de plantilla cuando el catálogo tenga formularios versionados
  (pendiente en el roadmap).
