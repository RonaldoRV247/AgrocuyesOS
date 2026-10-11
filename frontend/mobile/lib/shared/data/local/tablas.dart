import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// Esquema local (SQLite/Drift) espejo de `backend/.../V1__sync_core.sql`.
///
/// Tres decisiones heredadas del backend, no inventadas aqui:
///
/// 1. NOMBRES. Cada columna usa `.named('snake_case')` con el nombre EXACTO del
///    contrato del API (docs/04-api.md), y cada clase se traduce a la tabla del
///    server (Drift derivar `RegistroActividad` -> `registro_actividad`). El
///    payload del SyncWorker sale del propio snapshot de la fila: no hay un
///    mapa de traduccion que se pueda oxidar.
///
/// 2. TIEMPOS. `created_at` / `updated_at` son INTEGER epoch-millis, no fechas.
///    Es la unidad con la que arbitra LWW; un TEXT/TIMESTAMP local obligaria a
///    convertir zona en el camino y ahi es donde nacen los conflictos falsos.
///
/// 3. SIN FK DECLARADAS. A proposito. En el dispositivo el padre puede llegar
///    DESPUES que el hijo (una actividad de un terreno que aun no baja por pull
///    delta, o un registro creado en la web y todavia no sincronizado). El
///    backend resuelve lo mismo con `DEFERRABLE INITIALLY DEFERRED`; aqui la
///    equivalencia es no imponer restriccion y tratar `*_id` como referencia
///    logica. La integridad se vigila en la capa de repositorio, no en SQLite.
///
/// Ademas, `metadata` se guarda como TEXT con JSON (el equivalente local del
/// JSONB) y `deleted`/`deleted_at` como tombstone: borrar es estado replicable,
/// no ausencia de fila.
/// ---------------------------------------------------------------------------

/// ---------------------------------------------------------------------------
/// Core de tareas
/// ---------------------------------------------------------------------------

@DataClassName('TerrenoRow')
class Terreno extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  RealColumn get areaM2 => real().nullable().named('area_m2')();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();

  /// Null hasta cerrar el modulo de auth: hoy el server deriva `owner_id` del
  /// payload porque el JWT todavia no existe (docs/05). No se plantea vacio.
  TextColumn get ownerId => text().nullable().named('owner_id')();

  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable().named('deleted_at')();

  @override
  Set<GeneratedColumn> get primaryKey => {id};
}

@DataClassName('PlantillaProcesoRow')
class PlantillaProceso extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();

  /// Configuracion dinámica de la tarea renderizada por el cliente
  /// (icono, color, campos del formulario). Ver `TareaConfig`.
  TextColumn get metadata => text().withDefault(const Constant('{}'))();

  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable().named('deleted_at')();

  @override
  Set<GeneratedColumn> get primaryKey => {id};
}

/// La transaccion central del core de tareas.
@DataClassName('RegistroActividadRow')
class RegistroActividad extends Table {
  /// PK asignada por el dispositivo. El backend tiene una columna `client_uuid`
  /// separada con UNIQUE, pero siempre es igual al `id`
  /// (`RegistroActividad.crear` hace `clientUuid = getId()`), asi que localmente
  /// se guarda una sola vez y el SyncWorker la rellena en el payload.
  TextColumn get id => text()();

  TextColumn get terrenoId => text().named('terreno_id')();
  TextColumn get plantillaId => text().named('plantilla_id')();

  /// Copia del nombre de la plantilla al momento de crear el registro.
  /// Denormalizacion deliberada: la lista de actividades tiene que mostrar
  /// "Aporque" aunque el catalogo cambie o todavia no haya bajado por pull.
  TextColumn get plantillaNombre => text().withDefault(const Constant('')).named('plantilla_nombre')();

  /// `yyyy-MM-dd` local del dia trabajado (el backend la mapea a `LocalDate`).
  TextColumn get fechaRealizada => text().named('fecha_realizada')();

  /// CAMPOS DINAMICOS. Equivalente local del JSONB: aqui vive cualquier clave
  /// que el usuario defina (`kg_aplicados`, `humedad_pct`, `dose_ml`) sin
  /// ALTER TABLE ni deploy. Se escribe JSON PLANO y tipado (string/number/
  /// bool/array de escalares) y en snake_case con la unidad en la clave, para
  /// que el server lo indexe con `jsonb_path_ops` sin sorpresas (docs/02).
  ///
  /// Como TEXT no se puede indexar por contenido en SQLite: las busquedas por
  /// clave las hace el server; la app local filtra por terreno/fecha, que es lo
  /// que necesita la pantalla de campo.
  TextColumn get metadata => text().withDefault(const Constant('{}'))();

  TextColumn get ownerId => text().nullable().named('owner_id')();

  /// Deriva del formulario o del dispositivo usado. Permite auditar si un
  /// dato lo metio una persona o un futuro pipeline de IA (docs/07 Fase 4).
  TextColumn get fuente => text().withDefault(const Constant('manual'))();

  IntColumn get createdAt => integer().named('created_at')();

  /// Arbitro de LWW. Se reescribe en CADA edicion local con millis absolutos;
  /// nunca se deja en un valor menor (el server lo rechazaría como clock skew).
  IntColumn get updatedAt => integer().named('updated_at')();

  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable().named('deleted_at')();

  /// Null = nunca subio (la UI muestra el badge "sin sincronizar"). Con valor =
  /// el server confirmo INSERTED/APPLIED/DUPLICATE en ese instante. No participa
  /// en el arbitraje: solo alimenta el indicador de estado de sincronizacion.
  IntColumn get sincronizadoEn => integer().nullable().named('sincronizado_en')();

  @override
  Set<GeneratedColumn> get primaryKey => {id};
}

/// ---------------------------------------------------------------------------
/// Core de crianza (cuyes)
/// ---------------------------------------------------------------------------

@DataClassName('GalponRow')
class Galpon extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  IntColumn get capacidadMaxima => integer().nullable().named('capacidad_maxima')();
  TextColumn get ownerId => text().nullable().named('owner_id')();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable().named('deleted_at')();

  @override
  Set<GeneratedColumn> get primaryKey => {id};
}

@DataClassName('PozaRow')
class Poza extends Table {
  TextColumn get id => text()();
  TextColumn get galponId => text().named('galpon_id')();

  /// Etiqueta corta escrita a mano por el productor ("P-07"). Es el identificador
  /// que se ve en campo; el uuid manda en el sync.
  TextColumn get codigo => text()();

  IntColumn get hembras => integer().withDefault(const Constant(0))();
  IntColumn get machos => integer().withDefault(const Constant(0))();
  IntColumn get crias => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable().named('deleted_at')();
  IntColumn get sincronizadoEn => integer().nullable().named('sincronizado_en')();

  @override
  Set<GeneratedColumn> get primaryKey => {id};
}

@DataClassName('EventoPozaRow')
class EventoPoza extends Table {
  TextColumn get id => text()();
  TextColumn get pozaId => text().named('poza_id')();

  /// TEXT libre, nunca enum local: "Mortalidad", "Parto", "Vacunacion" y lo que
  /// el usuario invente vienen del catalogo. Agregar un tipo es un dato.
  TextColumn get tipoEvento => text().named('tipo_evento')();

  TextColumn get fechaEvento => text().named('fecha_evento')();

  /// Mismo trato que `metadata` de registro: JSON plano como texto.
  TextColumn get detalles => text().withDefault(const Constant('{}'))();

  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable().named('deleted_at')();
  IntColumn get sincronizadoEn => integer().nullable().named('sincronizado_en')();

  @override
  Set<GeneratedColumn> get primaryKey => {id};
}

/// ---------------------------------------------------------------------------
/// Infra local de sincronizacion (no se sincroniza nunca: vive solo en el
/// dispositivo)
/// ---------------------------------------------------------------------------

/// Outbox: la cola de cambios pendientes de subir.
///
/// Por que una tabla aparte y no un flag `sincronizado` en cada fila:
///  * El payload que se envia es el SNAPSHOT del momento del encolado. Si el
///    productor edita la misma fila mientras hay otra subida en vuelo, la
///    respuesta del server no puede confundirse con la version ya enviada.
///  * El order de reintentos/backoff es por cambio, no por entidad, y se lee con
///    un `ORDER BY seq` sin tocar las tablas de negocio.
///  * Un `STALE`/`REJECTED_DELETED` descarta UNA fila de la cola sin borrar el
///    dato local que el usuario todavia ve en pantalla.
@DataClassName('CambioPendienteRow')
class CambioPendiente extends Table {
  IntColumn get seq => integer().autoIncrement()();

  /// Nombre de entidad del contrato: registro_actividad, evento_poza, ...
  TextColumn get entity => text()();

  /// PK de la fila (el client_uuid). Junto con `entity` es la clave natural del
  /// outbox: reencolar el mismo registro reemplaza el cambio anterior.
  TextColumn get recordId => text().named('record_id')();

  /// `upsert` | `delete`. Nunca otro valor: el server lo rechaza.
  TextColumn get op => text().withDefault(const Constant('upsert'))();

  /// payload ya serializado, listo para POST /api/v1/sync/changes.
  TextColumn get payload => text()();

  /// `updated_at` absoluto que se envio/guardo con este cambio.
  IntColumn get updatedAt => integer().named('updated_at')();

  BoolColumn get pendiente => boolean().withDefault(const Constant(true))();

  IntColumn get intentos => integer().withDefault(const Constant(0))();

  /// Status del server (docs/04) o mensaje de red del ultimo intento. Alimenta
  /// el aviso en UI cuando el cambio NO se guardo (hay que decirle al productor
  /// por que, es criterio de aceptacion de la Fase 3).
  TextColumn get ultimoEstado => text().nullable().named('ultimo_estado')();

  IntColumn get creadaEn => integer().named('creada_en')();

  @override
  Set<GeneratedColumn> get primaryKey => {seq};
}

/// Key/value de estado del sync: watermark del pull delta, device_id, deriva de
/// reloj y ultima impresion de error.
@DataClassName('EstadoSyncRow')
class EstadoSync extends Table {
  TextColumn get clave => text()();
  TextColumn get valor => text()();

  @override
  Set<GeneratedColumn> get primaryKey => {clave};
}
