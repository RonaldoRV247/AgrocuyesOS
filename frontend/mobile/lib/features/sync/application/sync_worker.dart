import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../../core/utils/tiempo.dart';
import '../../../shared/data/local/app_database.dart';
import '../data/api_sync.dart';

class ResultadoSync {
  const ResultadoSync({
    this.enviados = 0,
    this.aceptados = 0,
    this.descartados = 0,
    this.rechazados = 0,
    this.falloDeRed = false,
    this.enVuelo = false,
    this.esperando = false,
  });

  final int enviados;
  final int aceptados;

  /// STALE / REJECTED_DELETED: el dispositivo perdio y adopta lo del server.
  final int descartados;

  /// REJECTED: payload invalido o clock skew. No se reintenta igual.
  final int rechazados;

  final bool falloDeRed;
  final bool enVuelo;
  final bool esperando;

  bool get hayQueAvisar => descartados > 0 || rechazados > 0;
}

/// ---------------------------------------------------------------------------
/// SyncWorker: vacia la cola de outbox contra `POST /api/v1/sync/changes`.
///
/// Reglas que salen del contrato del backend (docs/03, docs/04) y que este
/// cliente esta obligado a respetar:
///
///  * Un lote, no cambio por cambio. El server arbitra por lote y aborta todo
///    el lote ante error de persistencia: ahi la cola queda ENTERA pendiente y
///    se reintenta completa.
///  * `INSERTED`/`APPLIED`/`TOMBSTONED`/`DUPLICATE` -> sale de la cola.
///  * `STALE`/`REJECTED_DELETED` -> sale de la cola Y la fila local se reemplaza
///    con `server_payload`. Descartar sin adoptar deja al cliente convergiendo
///    a ciegas.
///  * `REJECTED` -> se queda pendiente, registra el estado para avisar en UI, y
///    se abandona tras N intentos (no es un error de red: reintentarlo igual es
///    desperdiciar bateria y datos).
///  * `server_timestamp` calibra el reloj local: sin eso, un dispositivo con el
///    reloj adelantado ganaria todos los LWW para siempre.
/// ---------------------------------------------------------------------------
class SyncWorker {
  SyncWorker({required AppDatabase db, required RelojCampo reloj, required ApiSync api})
      : _db = db,
        _reloj = reloj,
        _api = api;

  final AppDatabase _db;
  final RelojCampo _reloj;
  final ApiSync _api;

  static const int _tamanoLote = 40;
  static const int _maximoIntentos = 8;
  static const Duration _baseBackoff = Duration(seconds: 15);
  static const Duration _topeBackoff = Duration(minutes: 10);

  bool _enVuelo = false;
  int _milisUltimoFalloDeRed = 0;

  /// Identidad de dispositivo: nace localmente y se persiste (compartida con
  /// Auth). El backend ainda la acepta autodeclarada (docs/05), asi que NO se
  /// puede exponer el endpoint a produccion hasta que venga atada al token.
  Future<String> _deviceId() => _db.asegurarDeviceId();

  Future<ResultadoSync> sincronizarAhora() async {
    if (_enVuelo) return const ResultadoSync(enVuelo: true);

    final List<CambioPendienteRow> lote = await _db.lotePendiente(_tamanoLote);
    if (lote.isEmpty) return const ResultadoSync();

    if (_enBackoff(lote)) return const ResultadoSync(esperando: true);

    _enVuelo = true;
    try {
      final RespuestaSync respuesta = await _api.push(
        deviceId: await _deviceId(),
        changes: lote.map(_aCambio).toList(growable: false),
      );

      // Calibracion de reloj y watermark para el futuro pull delta.
      if (respuesta.serverTimestamp > 0) {
        _reloj.calibrarConServidor(respuesta.serverTimestamp);
        await _db.escribirEstado(ClavesSync.derivaReloj, '${_reloj.derivaMillis}');
        await _db.escribirEstado(ClavesSync.watermark, '${respuesta.serverTimestamp}');
        await _db.escribirEstado(ClavesSync.ultimaSubida, '${_reloj.ahoraMillis()}');
      }

      final ResultadoSync resultado = await _aplicarVeredictos(lote, respuesta);
      _milisUltimoFalloDeRed = 0; // una subida limpia corta el backoff
      return resultado;
    } on DioException catch (e) {
      // Fallo de transporte: la cola NO se toca (queda pendiente) y se anota el
      // motivo para que la UI diga "sin señal", no "error".
      _milisUltimoFalloDeRed = _reloj.ahoraMillis();
      final String motivo = e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.response == null
          ? 'SIN_RED'
          : 'HTTP_${e.response?.statusCode ?? 0}';
      for (final CambioPendienteRow c in lote) {
        await _db.marcarFallo(c.seq, motivo);
      }
      return ResultadoSync(enviados: lote.length, falloDeRed: true);
    } catch (_) {
      _milisUltimoFalloDeRed = _reloj.ahoraMillis();
      for (final CambioPendienteRow c in lote) {
        await _db.marcarFallo(c.seq, 'INESPERADO');
      }
      return ResultadoSync(enviados: lote.length, falloDeRed: true);
    } finally {
      _enVuelo = false;
    }
  }

  /// Entrada de los disparadores automaticos (red de vuelta, timer, jalar de la
  /// lista). Silenciosa por diseno: en campo el usuario no pide sincronizar.
  Future<void> intentarAutomatico() async {
    if (_enVuelo) return;
    await sincronizarAhora();
  }

  Future<ResultadoSync> _aplicarVeredictos(
    List<CambioPendienteRow> lote,
    RespuestaSync respuesta,
  ) async {
    final Map<String, CambioPendienteRow> porClave = <String, CambioPendienteRow>{
      for (final CambioPendienteRow c in lote) '${c.entity}|${c.recordId}': c,
    };

    int aceptados = 0;
    int descartados = 0;
    int rechazados = 0;

    for (final ResultadoCambio r in respuesta.results) {
      final CambioPendienteRow? fila = porClave['${r.entity}|${r.id}'];
      if (fila == null) continue;

      if (r.aceptado) {
        aceptados++;
        await _db.confirmar(fila.seq, r.entity, r.id, r.serverUpdatedAt ?? _reloj.ahoraMillis());
      } else if (r.descartable) {
        descartados++;
        await _db.descartar(fila.seq, r.status);
        await _adoptar(r);
      } else {
        rechazados++;
        if (fila.intentos + 1 >= _maximoIntentos) {
          await _db.descartar(fila.seq, 'ABANDONADO_${r.status}');
        } else {
          await _db.marcarFallo(fila.seq, r.status);
        }
      }
    }

    return ResultadoSync(
      enviados: lote.length,
      aceptados: aceptados,
      descartados: descartados,
      rechazados: rechazados,
    );
  }

  CambioSync _aCambio(CambioPendienteRow c) {
    Map<String, Object?> payload = <String, Object?>{};
    try {
      final Object? d = jsonDecode(c.payload);
      if (d is Map<String, dynamic>) payload = Map<String, Object?>.from(d);
    } catch (_) {
      // Un payload roto en la cola no puede frenar el resto del lote: el server
      // lo responderia REJECTED de todos modos y queda registrado.
      payload = <String, Object?>{};
    }
    return CambioSync(entity: c.entity, id: c.recordId, op: c.op, updatedAt: c.updatedAt, payload: payload);
  }

  /// El server devolvio su version porque gano el arbitraje (o porque el registro
  /// esta borrado en otro lado). Se sobrescribe la copia local CON SU timestamp y
  /// se marca como sincronizada: ya no queda nada que subir de esa fila.
  ///
  /// `created_at` se conserva si la fila ya existia; si no existia (llego desde
  /// la web), se siembra con la marca del server, porque en SQLite la columna es
  /// NOT NULL sin default y el upsert fallaria.
  Future<void> _adoptar(ResultadoCambio r) async {
    final Map<String, Object?>? p = r.serverPayload;
    if (p == null) return;
    final int marca = r.serverUpdatedAt ?? _reloj.ahoraMillis();

    switch (r.entity) {
      case Entidades.registroActividad:
        final RegistroActividadRow? previa = await _db.buscarRegistro(r.id);
        await _db.upsertRegistro(
          RegistroActividadCompanion(
            id: Value(r.id),
            terrenoId: Value('${p['terreno_id'] ?? previa?.terrenoId ?? ''}'),
            plantillaId: Value('${p['plantilla_id'] ?? previa?.plantillaId ?? ''}'),
            fechaRealizada: Value('${p['fecha_realizada'] ?? previa?.fechaRealizada ?? RelojCampo.hoyIso()}'),
            metadata: Value(jsonEncode(p['metadata'] ?? <String, Object?>{})),
            createdAt: Value(previa?.createdAt ?? marca),
            updatedAt: Value(marca),
            deleted: Value(r.serverDeleted),
            deletedAt: Value(r.serverDeleted ? marca : null),
            sincronizadoEn: Value(marca),
          ),
        );

      case Entidades.poza:
        final PozaRow? previa = await _db.buscarPoza(r.id);
        await _db.upsertPoza(
          PozaCompanion(
            id: Value(r.id),
            galponId: Value('${p['galpon_id'] ?? previa?.galponId ?? ''}'),
            codigo: Value('${p['codigo'] ?? previa?.codigo ?? ''}'),
            hembras: Value(_int(p['hembras'], previa?.hembras)),
            machos: Value(_int(p['machos'], previa?.machos)),
            crias: Value(_int(p['crias'], previa?.crias)),
            createdAt: Value(previa?.createdAt ?? marca),
            updatedAt: Value(marca),
            deleted: Value(r.serverDeleted),
            deletedAt: Value(r.serverDeleted ? marca : null),
            sincronizadoEn: Value(marca),
          ),
        );

      case Entidades.eventoPoza:
        final EventoPozaRow? previa = await _db.buscarEventoPoza(r.id);
        await _db.upsertEventoPoza(
          EventoPozaCompanion(
            id: Value(r.id),
            pozaId: Value('${p['poza_id'] ?? previa?.pozaId ?? ''}'),
            tipoEvento: Value('${p['tipo_evento'] ?? previa?.tipoEvento ?? 'Evento'}'),
            fechaEvento: Value('${p['fecha_evento'] ?? previa?.fechaEvento ?? RelojCampo.hoyIso()}'),
            detalles: Value(jsonEncode(p['detalles'] ?? <String, Object?>{})),
            createdAt: Value(previa?.createdAt ?? marca),
            updatedAt: Value(marca),
            deleted: Value(r.serverDeleted),
            deletedAt: Value(r.serverDeleted ? marca : null),
            sincronizadoEn: Value(marca),
          ),
        );
    }
  }

  /// Backoff exponencial sobre el numero de intentos ya gastados del lote.
  bool _enBackoff(List<CambioPendienteRow> lote) {
    if (_milisUltimoFalloDeRed == 0) return false;
    final int intentosMaximos = lote.map((c) => c.intentos).reduce(math.max);
    if (intentosMaximos == 0) return false;
    final int espera = math.min(
      _baseBackoff.inMilliseconds * (1 << math.min(intentosMaximos, 8)),
      _topeBackoff.inMilliseconds,
    );
    return _reloj.ahoraMillis() - _milisUltimoFalloDeRed < espera;
  }

  static int _int(Object? v, [int? defecto]) =>
      v is num ? v.toInt() : (int.tryParse('$v') ?? defecto ?? 0);
}
