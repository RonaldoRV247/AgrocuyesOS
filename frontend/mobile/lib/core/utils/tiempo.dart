import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUIDv4 generado en el dispositivo. Es la PK local Y la `client_uuid` que el
/// server usa como clave de idempotencia (`uq_registro_client_uuid`), por eso
/// nace aqui y nunca se reasigna: ver docs/02 y docs/03.
String nuevoUuidV4() => _uuid.v4();

/// ---------------------------------------------------------------------------
/// Reloj del dispositivo, con deriva corregida.
///
/// El LWW compara `updated_at` en epoch-millis ABSOLUTOS (UTC por definicion del
/// epoch: no hay zona horaria que traducir). Un reloj adelantado ganaria todos
/// los conflictos para siempre, y el server rechaza timestamps que excedan su
/// hora + `max-clock-skew-ms` (docs/03). Por eso el SyncWorker calibra la deriva
/// contra `server_timestamp` y TODO el codigo de dominio pide la hora a esta
/// instancia, nunca a `DateTime.now()`.
/// ---------------------------------------------------------------------------
class RelojCampo {
  int _derivaMillis = 0;

  /// Timestamp absoluto para `created_at` / `updated_at`.
  int ahoraMillis() => DateTime.now().millisecondsSinceEpoch + _derivaMillis;

  /// Calibracion despues de cualquier respuesta del sync.
  void calibrarConServidor(int serverTimestampMillis) {
    _derivaMillis = serverTimestampMillis - DateTime.now().millisecondsSinceEpoch;
  }

  /// Millis de diferencia (positivo = el reloj del equipo va atrasado). Sirve
  /// para avisar en UI si la deriva es sospechosamente grande.
  int get derivaMillis => _derivaMillis;

  /// `fecha_realizada` / `fecha_evento`: el dia de trabajo en el calendario
  /// LOCAL del productor (un turno que empieza a las 05:00 no es "ayer" solo
  /// porque el server este en otra zona). Se serializa como yyyy-MM-dd porque
  /// el backend la mapea a `LocalDate`.
  static String hoyIso() => fechaIso(DateTime.now());

  static String fechaIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
