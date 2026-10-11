import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../shared/di/config.dart';

/// Tokens en Keychain/Keystore, NUNCA en SharedPreferences ni en la base de
/// datos local: la BD la lee cualquier backup del telefono y el refresh token
/// de 90 dias es lo unico que hace falta para escribir en la cuenta de alguien.
class Sesion {
  const Sesion({
    required this.usuarioId,
    required this.email,
    required this.nombre,
    required this.accessToken,
    required this.refreshToken,
    required this.expiraEnMillis,
  });

  final String usuarioId;
  final String email;
  final String nombre;
  final String accessToken;
  final String refreshToken;

  /// Epoch-millis de vencimiento del ACCESS token (15 min segun docs/05).
  final int expiraEnMillis;

  bool get accessAPuntoOVencido => expiraEnMillis - kMargenRefrescoMillis <= DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toJson() => <String, Object?>{
        'usuario_id': usuarioId,
        'email': email,
        'nombre': nombre,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expira_en': expiraEnMillis,
      };

  factory Sesion.fromJson(Map<String, dynamic> j) => Sesion(
        usuarioId: '${j['usuario_id'] ?? j['sub'] ?? ''}',
        email: '${j['email'] ?? ''}',
        nombre: '${j['nombre'] ?? j['name'] ?? ''}',
        accessToken: '${j['access_token'] ?? ''}',
        refreshToken: '${j['refresh_token'] ?? ''}',
        // `expires_in` llega en segundos; se convierte a marca absoluta para no
        // comparar nunca contra un reloj con zona.
        expiraEnMillis: DateTime.now().millisecondsSinceEpoch +
            ((j['expires_in'] is num ? (j['expires_in'] as num).toInt() : 900) * 1000),
      );
}

class CredencialesGoogle {
  const CredencialesGoogle({required this.idToken, this.accessToken});

  final String idToken;
  final String? accessToken;
}

class InicioSesionCanceladoException implements Exception {}

/// Reuso de un refresh revocado, o token ya inservible: hay que volver a Google.
class SesionRevocadaException implements Exception {}

/// El contrato de auth esta disenado (docs/05) pero el backend aun no lo
/// implementa: hoy `/auth/token` responde 404 y la app debe seguir funcionando.
class AuthSinImplementarException implements Exception {}

abstract class ProveedorGoogle {
  /// Flujo interactivo.
  Future<CredencialesGoogle?> iniciarSesion();

  /// Sin UI: lo que hace "permanente" la sesion al reabrir la app.
  Future<CredencialesGoogle?> silencioso();

  Future<void> cerrarSesion();
}

class AdaptadorGoogleSignIn implements ProveedorGoogle {
  AdaptadorGoogleSignIn([GoogleSignIn? cliente])
      : _cliente = cliente ?? GoogleSignIn(scopes: <String>['email', 'profile']);

  final GoogleSignIn _cliente;

  @override
  Future<CredencialesGoogle?> iniciarSesion() async {
    final GoogleSignInAccount? cuenta = await _cliente.signIn();
    if (cuenta == null) return null; // cancelo: no es un error, es una eleccion
    final GoogleSignInAuthentication a = await cuenta.authentication;
    return CredencialesGoogle(idToken: a.idToken ?? '', accessToken: a.accessToken);
  }

  @override
  Future<CredencialesGoogle?> silencioso() async {
    final GoogleSignInAccount? cuenta = await _cliente.silentSignIn();
    if (cuenta == null) return null;
    final GoogleSignInAuthentication a = await cuenta.authentication;
    return CredencialesGoogle(idToken: a.idToken ?? '', accessToken: a.accessToken);
  }

  @override
  Future<void> cerrarSesion() => _cliente.signOut();
}

/// ---------------------------------------------------------------------------
/// Sesion persistente estilo WhatsApp: el access token es corto, el refresh
/// vive ~90 dias y se rota. Al abrir la app NO se pide login: se restaura la
/// sesion guardada y, si el access vencio, se refresca en segundo plano.
///
/// Importante para offline-first: si el refresh falla por falta de red, la
/// sesion se CONSERVA. El productor puede seguir registrando actividades todo
/// el dia sin token valido, porque la escritura es local y la cola sube cuando
/// vuelve la senal. Auth es un requisito del sync, no del captura.
/// ---------------------------------------------------------------------------
class AuthRepositorio {
  AuthRepositorio({
    required FlutterSecureStorage storage,
    required ProveedorGoogle google,
    required Dio http,
    required Future<String> Function() deviceId,
  })  : _storage = storage,
        _google = google,
        _http = http,
        _deviceId = deviceId;

  final FlutterSecureStorage _storage;
  final ProveedorGoogle _google;
  final Dio _http;
  final Future<String> Function() _deviceId;

  static const String _clave = 'agrocuyes.sesion';

  Future<Sesion?> restaurarSesion() async {
    final Sesion? local = await _leer();
    if (local == null) return null;

    if (!local.accessAPuntoOVencido) return local;

    try {
      final Sesion refrescada = await _refrescar(local);
      await _guardar(refrescada);
      return refrescada;
    } on SesionRevocadaException {
      await cerrarSesion();
      return null;
    } on AuthSinImplementarException {
      // Backend de auth pendiente: la sesion guardada sigue siendo util para el
      // resto de la app y no se rompe el arranque por un 404.
      return local;
    } catch (_) {
      return local; // sin red: se reintenta en el proximo arranque/uso
    }
  }

  Future<Sesion> iniciarConGoogle() async {
    final CredencialesGoogle? credenciales = await _google.iniciarSesion();
    if (credenciales == null || credenciales.idToken.isEmpty) {
      throw InicioSesionCanceladoException();
    }
    final Sesion sesion = await _post('/auth/token', <String, Object?>{
      'id_token': credenciales.idToken,
      'device_id': await _deviceId(),
    });
    await _guardar(sesion);
    return sesion;
  }

  /// Ruta de rotacion: el refresh usado queda revocado en el server. Si el
  /// servidor detecta reuso revoca toda la familia del `device_id` (docs/05).
  Future<Sesion> _refrescar(Sesion sesion) => _post('/auth/refresh', <String, Object?>{
        'refresh_token': sesion.refreshToken,
        'device_id': await _deviceId(),
      });

  Future<void> cerrarSesion() async {
    await _borrar();
    await _google.cerrarSesion();
  }

  Future<Sesion> _post(String ruta, Map<String, Object?> cuerpo) async {
    try {
      final Response<dynamic> r = await _http.post<dynamic>(ruta, data: jsonEncode(cuerpo));
      final Object? d = r.data;
      if (d is! Map<String, dynamic>) throw const FormatException('respuesta de auth sin cuerpo util');
      final Sesion sesion = Sesion.fromJson(d);
      if (sesion.accessToken.isEmpty) throw const FormatException('respuesta sin access_token');
      return sesion;
    } on DioException catch (e) {
      final int? codigo = e.response?.statusCode;
      if (codigo == 401 || codigo == 403) throw SesionRevocadaException();
      if (codigo == 404 || codigo == 501) throw AuthSinImplementarException();
      rethrow;
    }
  }

  Future<Sesion?> _leer() async {
    final String? crudo = await _storage.read(key: _clave);
    if (crudo == null || crudo.isEmpty) return null;
    try {
      final Object? d = jsonDecode(crudo);
      return d is Map<String, dynamic> ? Sesion.fromJson(d) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardar(Sesion s) =>
      _storage.write(key: _clave, value: jsonEncode(s.toJson()));

  Future<void> _borrar() => _storage.delete(key: _clave);
}
