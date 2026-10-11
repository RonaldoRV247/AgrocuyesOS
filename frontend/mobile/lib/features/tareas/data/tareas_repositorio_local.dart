import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/utils/tiempo.dart';
import '../../../shared/data/local/app_database.dart';
import '../domain/actividad.dart';
import '../domain/tarea_config.dart';
import '../domain/tareas_repositorio.dart';

/// Adaptador Drift del puerto [TareasRepositorio]. Aqui, y solo aqui, se toca
/// SQLite y se arma el payload del contrato de sync.
class TareasRepositorioLocal implements TareasRepositorio {
  TareasRepositorioLocal(this._db, this._reloj);

  final AppDatabase _db;
  final RelojCampo _reloj;

  @override
  Stream<List<TareaConfig>> watchPlantillas() {
    return _db.watchPlantillasActivas().map((filas) {
      final List<TareaConfig> plantillas = filas
          .map((f) => TareaConfig.fromMetadataTexto(
                plantillaId: f.id,
                nombre: f.nombre,
                metadataJson: f.metadata,
              ))
          .toList();
      // El orden lo decide el JSON (`ui.orden`), no un enum en el cliente.
      plantillas.sort((a, b) => a.orden.compareTo(b.orden));
      return plantillas;
    });
  }

  @override
  Stream<List<ActividadRegistrada>> watchRegistros(String terrenoId) {
    return _db.watchRegistrosDeTerreno(terrenoId).map((filas) => filas.map(_aDominio).toList());
  }

  @override
  Future<ActividadRegistrada> registrar({
    required String terrenoId,
    required TareaConfig plantilla,
    required Map<String, Object?> respuestas,
    String? fechaRealizada,
  }) async {
    // Identidad y tiempo nacen AQUI: el server nunca reinventa un id.
    final String id = nuevoUuidV4();
    final int ahora = _reloj.ahoraMillis();
    final String fecha = fechaRealizada ?? RelojCampo.hoyIso();
    final Map<String, Object?> metadata = plantilla.metadataDesde(respuestas);

    await _db.transaction(() async {
      await _db.upsertRegistro(
        RegistroActividadCompanion.insert(
          id: id,
          terrenoId: terrenoId,
          plantillaId: plantilla.plantillaId,
          plantillaNombre: Value(plantilla.nombre),
          fechaRealizada: fecha,
          metadata: Value(jsonEncode(metadata)),
          createdAt: ahora,
          updatedAt: ahora,
        ),
      );
      // Mismo transaction que la fila: un registro guardado y no encolado es un
      // registro que jamas llega al server, y eso no se puede detectar despues.
      await _db.encolar(
        entity: Entidades.registroActividad,
        recordId: id,
        payload: _payload(terrenoId: terrenoId, plantillaId: plantilla.plantillaId, fecha: fecha, metadata: metadata),
        updatedAt: ahora,
      );
    });

    return ActividadRegistrada(
      id: id,
      terrenoId: terrenoId,
      plantillaId: plantilla.plantillaId,
      plantillaNombre: plantilla.nombre,
      fechaRealizada: fecha,
      metadata: metadata,
      updatedAt: ahora,
    );
  }

  @override
  Future<ActividadRegistrada> editarMetadata({required String id, required Map<String, Object?> respuestas}) async {
    final RegistroActividadRow? actual = await _db.buscarRegistro(id);
    if (actual == null) throw StateError('registro inexistente: $id');

    final Map<String, Object?> previos = _decodificar(actual.metadata);
    final Map<String, Object?> merged = <String, Object?>{...previos, ...respuestas};
    final int ahora = _reloj.ahoraMillis();

    await _db.transaction(() async {
      await _db.upsertRegistro(
        RegistroActividadCompanion(
          id: Value(actual.id),
          terrenoId: Value(actual.terrenoId),
          plantillaId: Value(actual.plantillaId),
          plantillaNombre: Value(actual.plantillaNombre),
          fechaRealizada: Value(actual.fechaRealizada),
          metadata: Value(jsonEncode(merged)),
          ownerId: Value(actual.ownerId),
          fuente: Value(actual.fuente),
          createdAt: Value(actual.createdAt),
          // El timestamp SUBE: es la unica manera de que este cambio gane el
          // arbitraje LWW en el server. Un valor menor se rechazaria como STALE.
          updatedAt: Value(ahora),
          sincronizadoEn: const Value(null), // vuelve a "sin sincronizar"
        ),
      );
      await _db.encolar(
        entity: Entidades.registroActividad,
        recordId: id,
        payload: _payload(
          terrenoId: actual.terrenoId,
          plantillaId: actual.plantillaId,
          fecha: actual.fechaRealizada,
          metadata: merged,
        ),
        updatedAt: ahora,
      );
    });

    return _aDominio(await _db.buscarRegistro(id) ?? actual);
  }

  @override
  Future<void> borrar({required String id}) async {
    final RegistroActividadRow? actual = await _db.buscarRegistro(id);
    if (actual == null) return;
    final int ahora = _reloj.ahoraMillis();

    await _db.transaction(() async {
      await _db.upsertRegistro(
        RegistroActividadCompanion(
          id: Value(actual.id),
          terrenoId: Value(actual.terrenoId),
          plantillaId: Value(actual.plantillaId),
          plantillaNombre: Value(actual.plantillaNombre),
          fechaRealizada: Value(actual.fechaRealizada),
          metadata: Value(actual.metadata),
          ownerId: Value(actual.ownerId),
          fuente: Value(actual.fuente),
          createdAt: Value(actual.createdAt),
          updatedAt: Value(ahora),
          deleted: const Value(true),
          deletedAt: Value(ahora),
          sincronizadoEn: const Value(null),
        ),
      );
      // `op=delete` solo necesita el id: con `loadForUpdate` vacio el server
      // responde TOMBSTONED y con tombstone vigente, REJECTED_DELETED.
      await _db.encolar(
        entity: Entidades.registroActividad,
        recordId: id,
        payload: '{}',
        updatedAt: ahora,
        op: 'delete',
      );
    });
  }

  /// snake_case EXACTO del contrato (docs/04). `client_uuid` no va en el
  /// payload: el server lo deriva del `id` del cambio.
  String _payload({
    required String terrenoId,
    required String plantillaId,
    required String fecha,
    required Map<String, Object?> metadata,
  }) =>
      jsonEncode(<String, Object?>{
        'terreno_id': terrenoId,
        'plantilla_id': plantillaId,
        'fecha_realizada': fecha,
        'metadata': metadata,
      });

  ActividadRegistrada _aDominio(RegistroActividadRow f) => ActividadRegistrada(
        id: f.id,
        terrenoId: f.terrenoId,
        plantillaId: f.plantillaId,
        plantillaNombre: f.plantillaNombre.isEmpty ? f.plantillaId : f.plantillaNombre,
        fechaRealizada: f.fechaRealizada,
        metadata: _decodificar(f.metadata),
        updatedAt: f.updatedAt,
        sincronizadoEn: f.sincronizadoEn,
      );

  Map<String, Object?> _decodificar(String texto) {
    try {
      final Object? d = jsonDecode(texto.isEmpty ? '{}' : texto);
      return d is Map<String, dynamic> ? Map<String, Object?>.from(d) : <String, Object?>{};
    } catch (_) {
      // Una metadata corrompida no puede tapar el historial del lote.
      return <String, Object?>{};
    }
  }
}
