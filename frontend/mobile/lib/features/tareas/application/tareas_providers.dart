import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/di/inyeccion.dart';
import '../data/tareas_repositorio_local.dart';
import '../domain/actividad.dart';
import '../domain/tarea_config.dart';
import '../domain/tareas_repositorio.dart';

/// La composicion de infraestructura compartida (BD, reloj) esta en
/// `shared/di/inyeccion.dart`: aca solo lo que es propio de esta feature.

final tareasRepositorioProvider = Provider<TareasRepositorio>((ref) =>
    TareasRepositorioLocal(ref.watch(baseDeDatosProvider), ref.watch(relojProvider)));

/// ---------------------------------------------------------------------------
/// Lecturas: StreamProvider sobre `watch()` de Drift. Es lo que da la
/// reactividad "instantanea sin bloqueos": no hay `FutureBuilder` re-leyendo ni
/// `notifyListeners` manual; la consulta de SQLite emite y Riverpod reconstruye
/// solo los widgets suscritos.
/// ---------------------------------------------------------------------------

/// Catalogo dinamico -> la cuadrilla de botones. Incluye plantillas nuevas en
/// cuanto el sync las escribe localmente.
final plantillasProvider = StreamProvider<List<TareaConfig>>(
  (ref) => ref.watch(tareasRepositorioProvider).watchPlantillas(),
);

/// Historial del lote. `family` para cambiar de terreno sin recargar la app.
final registrosDelTerrenoProvider = StreamProvider.family<List<ActividadRegistrada>, String>(
  (ref, terrenoId) => ref.watch(tareasRepositorioProvider).watchRegistros(terrenoId),
);

/// Terreno "actual": el primero disponible. Manana sera una seleccion explicita
/// guardada en `estado_sync`; hoy evita un paso en la pantalla del productor.
final terrenoActivoProvider = FutureProvider<String?>((ref) async {
  final List<TerrenoRow> terrenos = await ref.watch(baseDeDatosProvider).traerTerrenosActivos();
  return terrenos.isEmpty ? null : terrenos.first.id;
});

/// ---------------------------------------------------------------------------
/// Escrituras
/// ---------------------------------------------------------------------------

/// Caso de uso expuesto como provider: el widget lo llama y la UI se actualiza
/// sola por el stream, no con un `refresh()` posterior.
class GuardarTarea {
  GuardarTarea(this._repo);

  final TareasRepositorio _repo;

  Future<ActividadRegistrada> call({
    required String terrenoId,
    required TareaConfig plantilla,
    required Map<String, Object?> respuestas,
  }) {
    final List<String> faltantes = plantilla.faltantes(respuestas);
    if (faltantes.isNotEmpty) throw FaltaCampoException(faltantes);
    return _repo.registrar(terrenoId: terrenoId, plantilla: plantilla, respuestas: respuestas);
  }
}

final guardarTareaProvider = Provider<GuardarTarea>(
  (ref) => GuardarTarea(ref.watch(tareasRepositorioProvider)),
);

final borrarTareaProvider = Provider<Future<void> Function(String id)>((ref) {
  // Se captura el repositorio ya resuelto: `ref` no debe vivir dentro del
  // closure que llama el widget (puede ejecutarse despues del dispose).
  final TareasRepositorio repo = ref.watch(tareasRepositorioProvider);
  return (String id) => repo.borrar(id: id);
});

class FaltaCampoException implements Exception {
  FaltaCampoException(this.claves);

  final List<String> claves;

  @override
  String toString() => 'Faltan campos obligatorios: ${claves.join(', ')}';
}
