import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/tiempo.dart';
import 'tablas.dart';

part 'app_database.g.dart';

/// Claves de `estado_sync`. Son datos, no columnas: el pull delta del roadmap
/// (docs/07 Fase 1) ya encuentra el watermark listo aqui.
class ClavesSync {
  static const String watermark = 'watermark_updated_at';
  static const String deviceId = 'device_id';
  static const String derivaReloj = 'clock_drift_ms';
  static const String ultimaSubida = 'ultima_subida_ok';
}

/// Nombres de entidad del contrato de sync (docs/04-api.md). Copiados tal cual:
/// una entidad no soportada no es error HTTP, es `status=REJECTED`, y se ve feo.
class Entidades {
  static const String terreno = 'terreno';
  static const String plantillaProceso = 'plantilla_proceso';
  static const String registroActividad = 'registro_actividad';
  static const String galpon = 'galpon';
  static const String poza = 'poza';
  static const String eventoPoza = 'evento_poza';
}

@DriftDatabase(
  tables: [
    Terreno,
    PlantillaProceso,
    RegistroActividad,
    Galpon,
    Poza,
    EventoPoza,
    CambioPendiente,
    EstadoSync,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          //Indices espejo de V1__sync_core.sql. En SQLite no existen los
          //indices parciales `WHERE deleted = false` del server, pero si los
          //compuestos que usan las pantallas de campo.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_registro_terreno '
            'ON registro_actividad (terreno_id, fecha_realizada DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_registro_updated_at '
            'ON registro_actividad (updated_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_evento_poza_tipo '
            'ON evento_poza (poza_id, tipo_evento, fecha_evento DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_cola_pendiente '
            'ON cambio_pendiente (pendiente, seq)',
          );
        },
        onUpgrade: (m, from, to) async {
          // Cada version futura suma aqui su `m.createTable`/`alterTable`. Se
          // deja explicito porque una app de campo NO puede perder registros al
          // actualizar: antes de subir la version hay que hacer backup del file.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
          // SIN PRAGMA foreign_keys: las referencias son logicas a proposito
          // (ver cabecera de tablas.dart).
        },
      );

  /// ---------------------------------------------------------------------------
  /// Lecturas reactivas: TODO lo que consume la UI es `watch()`. Riverpod se
  /// suscribe al stream y la pantalla se actualiza en el mismo instante de la
  /// escritura, sin `setState` manual ni `refresh()` luego de guardar.
  /// ---------------------------------------------------------------------------

  Stream<List<RegistroActividadRow>> watchRegistrosDeTerreno(String terrenoId) {
    return (select(registroActividad)
          ..where((t) => t.terrenoId.equals(terrenoId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaRealizada), OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  Stream<List<PlantillaProcesoRow>> watchPlantillasActivas() {
    return (select(plantillaProceso)
          ..where((t) => t.activo.equals(true) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.nombre)]))
        .watch();
  }

  Future<List<TerrenoRow>> traerTerrenosActivos() {
    return (select(terreno)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.nombre)]))
        .get();
  }

  Future<List<GalponRow>> traerGalponesActivos() {
    return (select(galpon)
          ..where((t) => t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.nombre)]))
        .get();
  }

  Stream<List<PozaRow>> watchPozasDeGalpon(String galponId) {
    return (select(poza)
          ..where((t) => t.galponId.equals(galponId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.codigo)]))
        .watch();
  }

  Stream<List<EventoPozaRow>> watchEventosDePoza(String pozaId, {int limite = 30}) {
    return (select(eventoPoza)
          ..where((t) => t.pozaId.equals(pozaId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaEvento), OrderingTerm.desc(t.updatedAt)])
          ..limit(limite))
        .watch();
  }

  /// Badge de "sin sincronizar" en la barra superior. Reacciona a la cola, no a
  /// un contador en memoria que se pierde al reiniciar la app.
  Stream<int> watchCantidadPendientes() {
    return (select(cambioPendiente)..where((t) => t.pendiente.equals(true)))
        .watch()
        .map((filas) => filas.length);
    // Cola larga (miles de filas) -> cambiar por selectOnly + countAll().
  }

  /// ---------------------------------------------------------------------------
  /// Escrituras
  /// ---------------------------------------------------------------------------

  Future<void> upsertRegistro(RegistroActividadCompanion c) =>
      into(registroActividad).insertOnConflictUpdate(c);

  Future<void> upsertEventoPoza(EventoPozaCompanion c) =>
      into(eventoPoza).insertOnConflictUpdate(c);

  Future<void> upsertPoza(PozaCompanion c) => into(poza).insertOnConflictUpdate(c);

  Future<void> upsertTerreno(TerrenoCompanion c) => into(terreno).insertOnConflictUpdate(c);

  Future<void> upsertGalpon(GalponCompanion c) => into(galpon).insertOnConflictUpdate(c);

  Future<void> upsertPlantilla(PlantillaProcesoCompanion c) =>
      into(plantillaProceso).insertOnConflictUpdate(c);

  Future<RegistroActividadRow?> buscarRegistro(String id) =>
      (select(registroActividad)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<PozaRow?> buscarPoza(String id) =>
      (select(poza)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<EventoPozaRow?> buscarEventoPoza(String id) =>
      (select(eventoPoza)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Encola un cambio. Reemplaza cualquier cambio anterior pendiente del MISMO
  /// registro: el LWW del server reemplaza el payload completo (no lo parchea),
  /// asi que mandar dos versiones del mismo registro es trabajo inutil y
  /// ruido en la cola.
  Future<void> encolar({
    required String entity,
    required String recordId,
    required String payload,
    required int updatedAt,
    String op = 'upsert',
  }) {
    return transaction(() async {
      await (delete(cambioPendiente)
            ..where((t) => t.entity.equals(entity) & t.recordId.equals(recordId) & t.pendiente.equals(true)))
          .go();
      await into(cambioPendiente).insert(
        CambioPendienteCompanion.insert(
          entity: entity,
          recordId: recordId,
          op: op,
          payload: payload,
          updatedAt: updatedAt,
          creadaEn: updatedAt,
        ),
      );
    });
  }

  /// Lote a subir, en orden de encolado.
  Future<List<CambioPendienteRow>> lotePendiente(int limite) {
    return (select(cambioPendiente)
          ..where((t) => t.pendiente.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)])
          ..limit(limite))
        .get();
  }

  /// El server acepto (INSERTED/APPLIED/TOMBSTONED/DUPLICATE): sale de la cola y
  /// la fila local marca su badge como sincronizado.
  Future<void> confirmar(int seq, String entity, String recordId, int millis) {
    return transaction(() async {
      await (update(cambioPendiente)..where((t) => t.seq.equals(seq)))
          .write(const CambioPendienteCompanion(pendiente: Value(false), ultimoEstado: Value('OK')));
      await _marcarSincronizado(entity, recordId, millis);
    });
  }

  /// STALE / REJECTED_DELETED: sale de la cola. La adopcion del `server_payload`
  /// la hace el SyncWorker (es logica de contrato, no de acceso a datos), porque
  /// ahi se decodifica el JSON y se mapea a la fila local.
  Future<void> descartar(int seq, String estado) {
    return (update(cambioPendiente)..where((t) => t.seq.equals(seq)))
        .write(CambioPendienteCompanion(pendiente: const Value(false), ultimoEstado: Value(estado)));
  }

  /// Fallo de red o `REJECTED`: queda pendiente y suma un intento, que es lo que
  /// activa el backoff. Se incrementa en SQL para no leer-modificar-escribir.
  Future<void> marcarFallo(int seq, String estado) {
    return customUpdate(
      'UPDATE cambio_pendiente SET intentos = intentos + 1, ultimo_estado = ? WHERE seq = ?',
      variables: [Variable.withString(estado), Variable.withInt(seq)],
    );
  }

  Future<void> _marcarSincronizado(String entity, String recordId, int millis) async {
    switch (entity) {
      case Entidades.registroActividad:
        await (update(registroActividad)..where((t) => t.id.equals(recordId)))
            .write(RegistroActividadCompanion(sincronizadoEn: Value(millis)));
      case Entidades.eventoPoza:
        await (update(eventoPoza)..where((t) => t.id.equals(recordId)))
            .write(EventoPozaCompanion(sincronizadoEn: Value(millis)));
      case Entidades.poza:
        await (update(poza)..where((t) => t.id.equals(recordId)))
            .write(PozaCompanion(sincronizadoEn: Value(millis)));
    }
  }

  /// ---------------------------------------------------------------------------
  /// Estado del sync
  /// ---------------------------------------------------------------------------

  Future<String?> leerEstado(String clave) async {
    final fila = await (select(estadoSync)..where((t) => t.clave.equals(clave))).getSingleOrNull();
    return fila?.valor;
  }

  Future<void> escribirEstado(String clave, String valor) {
    return into(estadoSync).insertOnConflictUpdate(
      EstadoSyncCompanion.insert(clave: clave, valor: valor),
    );
  }

  /// Identidad del dispositivo: nace la primera vez y no cambia nunca, porque es
  /// como el server agrupa los refresh tokens y audita las subidas. Compartido
  /// por el SyncWorker y por Auth para que ambos hablen del mismo id.
  Future<String> asegurarDeviceId() async {
    final String? guardado = await leerEstado(ClavesSync.deviceId);
    if (guardado != null && guardado.isNotEmpty) return guardado;
    final String nuevo = 'device-${nuevoUuidV4()}';
    await escribirEstado(ClavesSync.deviceId, nuevo);
    return nuevo;
  }
}

/// ---------------------------------------------------------------------------
/// Apertura. WAL + escrituras de una sola fila mantienen el write en ~1ms, asi
/// que el tap del boton gigante responde sin frame perdido. Si el catalogo
/// crece y se necesitan consultas pesadas (reportes sobre miles de registros),
/// cambiar `NativeDatabase(file)` por `NativeDatabase.createInBackground(file)`
/// de este mismo paquete mueve SQLite a un isolate secundario sin tocar una
/// linea de la capa superior.
/// ---------------------------------------------------------------------------
LazyDatabase conectar() {
  return LazyDatabase(() async {
    final carpeta = await getApplicationDocumentsDirectory();
    final archivo = File(p.join(carpeta.path, 'agrocuyes.sqlite'));
    return NativeDatabase(archivo);
  });
}
