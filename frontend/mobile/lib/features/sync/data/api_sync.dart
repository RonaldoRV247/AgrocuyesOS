import 'dart:convert';

import 'package:dio/dio.dart';

/// Cambio listo para `POST /api/v1/sync/changes`. Los nombres de clave son los
/// del contrato (snake_case fijado por la estrategia de nombres del backend).
class CambioSync {
  const CambioSync({
    required this.entity,
    required this.id,
    required this.op,
    required this.updatedAt,
    required this.payload,
  });

  final String entity;

  /// UUIDv4 del dispositivo: viaja como `id` y el server lo trata como
  /// `client_uuid` (clave de idempotencia).
  final String id;
  final String op;
  final int updatedAt;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
        'entity': entity,
        'id': id,
        'op': op,
        'updated_at': updatedAt,
        'payload': payload,
      };
}

/// Veredicto del arbitraje LWW para un cambio (docs/04-api.md).
class ResultadoCambio {
  const ResultadoCambio({
    required this.entity,
    required this.id,
    required this.status,
    this.serverUpdatedAt,
    this.serverDeleted = false,
    this.serverPayload,
  });

  final String entity;
  final String id;
  final String status;
  final int? serverUpdatedAt;
  final bool serverDeleted;
  final Map<String, Object?>? serverPayload;

  bool get aceptado => const <String>{'INSERTED', 'APPLIED', 'TOMBSTONED', 'DUPLICATE'}.contains(status);
  bool get descartable => status == 'STALE' || status == 'REJECTED_DELETED';

  factory ResultadoCambio.fromJson(Map<String, dynamic> j) {
    final Object? p = j['server_payload'];
    return ResultadoCambio(
      entity: '${j['entity'] ?? ''}',
      id: '${j['id'] ?? ''}',
      status: '${j['status'] ?? 'REJECTED'}',
      serverUpdatedAt: j['server_updated_at'] is num ? (j['server_updated_at'] as num).toInt() : null,
      serverDeleted: j['server_deleted'] == true,
      serverPayload: p is Map<String, dynamic> ? Map<String, Object?>.from(p) : null,
    );
  }
}

class RespuestaSync {
  const RespuestaSync({
    required this.serverTimestamp,
    required this.accepted,
    required this.rejected,
    required this.results,
  });

  final int serverTimestamp;
  final int accepted;
  final int rejected;
  final List<ResultadoCambio> results;

  factory RespuestaSync.fromJson(Map<String, dynamic> j) {
    final List<ResultadoCambio> resultados = <ResultadoCambio>[];
    final Object? crudo = j['results'];
    if (crudo is List) {
      for (final Object? r in crudo) {
        if (r is Map<String, dynamic>) resultados.add(ResultadoCambio.fromJson(r));
      }
    }
    return RespuestaSync(
      // Sin server_timestamp no hay calibracion de reloj: se usa 0 como
      // "no informar" y el worker no toca la deriva.
      serverTimestamp: j['server_timestamp'] is num ? (j['server_timestamp'] as num).toInt() : 0,
      accepted: j['accepted'] is num ? (j['accepted'] as num).toInt() : 0,
      rejected: j['rejected'] is num ? (j['rejected'] as num).toInt() : 0,
      results: resultados,
    );
  }
}

class ApiSync {
  ApiSync({required String baseUrl, Dio? dio, Future<String?> Function()? tokenProvider})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: <String, Object?>{'Content-Type': 'application/json'},
            )),
        _tokenProvider = tokenProvider {
    // Bearer condicional: hoy el endpoint esta abierto (docs/05 sin
    // implementar), y manana la app no puede subir nada sin token. Se resuelve
    // por request para que un refresh en vuelo se vea inmediatamente.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final String? token = await _tokenProvider?.call();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final Future<String?> Function()? _tokenProvider;

  Future<RespuestaSync> push({required String deviceId, required List<CambioSync> changes}) async {
    final Response<dynamic> r = await _dio.post<dynamic>(
      '/api/v1/sync/changes',
      data: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'changes': changes.map((c) => c.toJson()).toList(),
      }),
    );
    final Object? d = r.data;
    if (d is Map<String, dynamic>) return RespuestaSync.fromJson(d);
    throw const FormatException('respuesta de sync sin cuerpo util');
  }

  /// Pull delta: todavia NO existe en el server (docs/07, Fase 1). Se deja el
  /// hueco tipado para que el SyncWorker no tenga que cambiar cuando llegue.
  Future<RespuestaSync> pull({required int desdeWatermark}) async {
    throw UnimplementedError('GET /api/v1/sync/changes?since= pendiente en el backend');
  }
}
