import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/app_database.dart';
import '../../core/utils/tiempo.dart';

/// ---------------------------------------------------------------------------
/// Composicion compartida por TODAS las features (tareas, crianza, sync, auth).
/// Vive aqui y no dentro de una feature para que `features/crianza` no tenga
/// que importar `features/tareas` para abrir la base de datos.
/// ---------------------------------------------------------------------------

final baseDeDatosProvider = Provider<AppDatabase>((ref) {
  final AppDatabase db = AppDatabase(conectar());
  // Cerrar al morir el ProviderScope (fin de la app). Las streams activas hacen
  // que el GC no sea una opcion.
  ref.onDispose(db.close);
  return db;
});

/// Unica fuente de timestamps de la app: epoch-millis con la deriva de reloj
/// ya corregida contra `server_timestamp` (docs/03).
final relojProvider = Provider<RelojCampo>((ref) => RelojCampo());

/// Badge de "sin sincronizar" de la barra superior.
final cambiosPendientesProvider = StreamProvider<int>(
  (ref) => ref.watch(baseDeDatosProvider).watchCantidadPendientes(),
);
