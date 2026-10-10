# 06 · Decisiones de arquitectura

Cada decisión con su alternativa descartada y el motivo real (varias salieron de
fallar en ejecución, no de una discusión teórica).

## D1 · PK UUIDv4 asignada por el cliente, no generada por la BD

Motivo: una fila creada offline necesita su identidad **antes** de tener señal;
si el server asigna el id, el reintento de la cola duplica la fila. El UUID del
cliente es además la clave de idempotencia del protocolo.
Descartado: `bigserial` + columna `client_uuid` separada (doble identidad,
mapeos extra); `uuid DEFAULT gen_random_uuid()` como única fuente (el server no
puede imponer su id a un lote offline).

## D2 · `@Id` sin generador + `@Version` nullable para distinguir transient/detached

Motivo: con PK asignada, Hibernate no puede saber si "id no nulo" significa
"nueva" o "ya existe". Comprobado en ejecución: con `@UuidGenerator` puesto,
`persist()` lanzaba `PersistentObjectException` ("detached entity passed to
persist") y con `merge()` degeneraba en un UPDATE de 0 filas
(`OptimisticLockException`). `@Version Long` nulo → transient → INSERT.
Descartado: `Persistable<UUID>` con un flag `isNew` (resuelve igual, pero mete
spring-data-commons en el dominio y es un contrato más fácil de romper).
**Advertencia permanente**: `version` no es el reloj de conflicto. Ese es
`updated_at`. Confundirlas volvería el LWW dependiente de un contador local.

## D3 · `updated_at` como epoch-millis (BIGINT), no `TIMESTAMPTZ`

Motivo: LWW es una comparación de enteros entre reloj del dispositivo y reloj del
server; con tipos temporales aparecen conversión de zona, precisión y
serialización ISO como fuente de bugs. Descartado: `TIMESTAMPTZ` +
`EXTRACT(epoch…)` en las comparaciones.

## D4 · Catálogos dinámicos con claves string, sin enums

Motivo: "un tipo de actividad nuevo" es un caso de uso normal del productor, no
una excepción. Un enum obliga a deploy + migración + release móvil (con
actualización de app en zona sin conectividad). Las claves de enrutamiento del
API (`entity`) son strings normalizados por el mismo motivo.
Riesgo aceptado: no hay validación de dominio cerrada sobre el valor; se
compensa con `varchar` acotado y con el catálogo versionado del roadmap.

## D5 · JSONB para atributos variables

Motivo: es la condición para que la ingesta IA añada campos sin `ALTER TABLE`.
Además permite consultar por dentro del JSON (`@>`, `->>`) y crear índice GIN.
Descartado: tabla EAV (`atributo_valor`) — consultas terriblemente más caras y
sin tipado; columnas fijas por tipo de actividad — el requisito que queremos
evitar.
Nota JDBC: el operador `?` de jsonb colisiona con los placeholders del driver
(PgJDBC lo trata como parámetro). Usar `jsonb_exists(col, 'clave')` o escapar.

## D6 · Borrados como estado (tombstone) y pegajosos

Motivo: sin tombstone, un borrado no se propaga y el registro reaparece en el
otro dispositivo. Que un `upsert` más nuevo no lo reviva evita el efecto
zombie de colas offline atrasadas. Costo aceptado: no existe "restaurar".

## D7 · Bloqueo pesimista por PK en el arbitraje

Motivo: el LWW es un read-modify-write; dos lotes concurrentes sobre el mismo
registro pueden leer el mismo estado y escribir ambos. `SELECT … FOR UPDATE`
dentro de la transacción del lote lo cierra.
Descartado: `@Version` como bloqueo optimista con rebote al cliente (el cliente
ya está en una cola offline; rebotarle conflictos es peor que serializar).

## D8 · Una transacción por lote, pero fallos de validación cambio por cambio

Motivo: una fila corrupta en la cola no debe bloquear las demás, así que el
handler valida el payload y devuelve `REJECTED` **antes** de tocar la BD.
Los errores de persistencia sí abortan el lote: PostgreSQL aborta la
transacción en el primer error SQL, y capturarlos produce
`UnexpectedRollbackException` al commit (bug real encontrado en ejecución).

## D9 · FK `DEFERRABLE INITIALLY DEFERRED`

Motivo: un lote offline puede traer la actividad antes que el terreno. Con FK
inmediata el lote falla por orden de arrival, no por datos. Se verifica al
commit, que es justo la semántica que quiere un sistema de colas.
Consecuencia: una FK rota se detecta al final del lote → el lote completo se
revierte (coherente con D8).

## D10 · `SyncRepository` genérico por tipo de entidad (un adapter, no seis)

Motivo: la operación es siempre la misma sobre la PK (`loadForUpdate`,
`insert`, `update`); seis clases espejo hubieran sido seis oportunidades de
divergir en el bloqueo o en el merge. El tipo se fija en el `@Bean`.
Contraparte: el puerto separa `insert` de `update` a propósito (ver D2), y ese
contrato lo heredaron también los tests en memoria.

## D11 · Contrato del API en snake_case

Motivo: es el formato del JSONB que viaja dentro del payload; mezclar
camelCase en el envoltorio y snake_case en el contenido confunde al cliente y a
las consultas posteriores. Se fijó con una propiedad global de Jackson.
