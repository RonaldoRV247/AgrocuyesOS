import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../shared/di/config.dart';
import '../../../shared/di/inyeccion.dart';
import '../data/auth_repositorio.dart';

/// Keystore/Keychain. `first_unlock` en iOS para que el SyncWorker en segundo
/// plano pueda leer el token sin despertar al usuario.
final almacenamientoSeguroProvider = Provider<FlutterSecureStorage>(
  (ref) => FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  ),
);

final authHttpProvider = Provider<Dio>(
  (ref) => Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: <String, Object?>{'Content-Type': 'application/json'},
  )),
);

final proveedorGoogleProvider = Provider<ProveedorGoogle>((ref) => AdaptadorGoogleSignIn());

final authRepositorioProvider = Provider<AuthRepositorio>((ref) => AuthRepositorio(
      storage: ref.watch(almacenamientoSeguroProvider),
      google: ref.watch(proveedorGoogleProvider),
      http: ref.watch(authHttpProvider),
      deviceId: () => ref.watch(baseDeDatosProvider).asegurarDeviceId(),
    ));

/// ---------------------------------------------------------------------------
/// Sesion persistente: el primer `build()` restaura lo guardado y refresca en
/// silencio si hace falta. La pantalla nunca muestra un login obligatorio: sin
/// sesion la app captura datos igual y solo avisa que no podra subirlos.
/// ---------------------------------------------------------------------------
class ControladorSesion extends AutoDisposeAsyncNotifier<Sesion?> {
  @override
  Future<Sesion?> build() => ref.read(authRepositorioProvider).restaurarSesion();

  Future<void> iniciarConGoogle() async {
    state = const AsyncValue<Sesion?>.loading();
    state = await AsyncValue.guard<Sesion?>(() => ref.read(authRepositorioProvider).iniciarConGoogle());
  }

  Future<void> cerrarSesion() async {
    await ref.read(authRepositorioProvider).cerrarSesion();
    state = const AsyncValue<Sesion?>.data(null);
  }
}

final sesionProvider = AsyncNotifierProvider.autoDispose<ControladorSesion, Sesion?>(
  ControladorSesion.new,
);
