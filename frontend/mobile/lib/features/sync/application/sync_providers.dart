import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/di/config.dart';
import '../../../shared/di/inyeccion.dart';
import '../../auth/application/auth_providers.dart';
import '../data/api_sync.dart';
import 'sync_worker.dart';

final apiSyncProvider = Provider<ApiSync>(
  (ref) => ApiSync(
    baseUrl: kBaseUrl,
    // El Bearer se resuelve por request: un refresh en vuelo se ve de inmediato
    // en la proxima subida, sin reconstruir el cliente HTTP.
    tokenProvider: () async => ref.read(sesionProvider).valueOrNull?.accessToken,
  ),
);

final syncWorkerProvider = Provider<SyncWorker>((ref) => SyncWorker(
      db: ref.watch(baseDeDatosProvider),
      reloj: ref.watch(relojProvider),
      api: ref.watch(apiSyncProvider),
    ));

/// `none` en una zona rural es la condicion normal, no la excepcion: cualquier
/// suscriptor que dependa de esto tiene que tratar la ausencia de red como un
/// estado de diseno, no como un error.
final conectividadProvider = StreamProvider<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none));
});

/// ---------------------------------------------------------------------------
/// Disparadores automaticos. Se instalan una sola vez desde el ProviderScope y
/// se desinstalan con el scope: es el unico "sistema operativo" de la app.
///
///  * Rebote de conectividad (4G que vuelve 3 segundos en un cerro) -> subir.
///  * Timer de respaldo por si el broadcast de conectividad no llega.
///  * La cola reacciona sola: el badge se ve en [cambiosPendientesProvider].
/// ---------------------------------------------------------------------------
final sincronizacionAutomaticaProvider = Provider<void>((ref) {
  final SyncWorker worker = ref.watch(syncWorkerProvider);

  Timer? programado;
  programado = Timer.periodic(const Duration(seconds: 45), (_) => worker.intentarAutomatico());

  // El stream emite AsyncValue, no bool: hay que mirar el valor, o el rebote de
  // red nunca se traduciria en un intento de subida.
  ref.listen<AsyncValue<bool>>(conectividadProvider, (_, AsyncValue<bool> estado) {
    if (estado.valueOrNull == true) worker.intentarAutomatico();
  });

  // Primer intento tibio al arrancar: si hay red y cola de ayer, sube sin que
  // el productor toque nada.
  unawaited(worker.intentarAutomatico());

  ref.onDispose(() => programado?.cancel());
});
