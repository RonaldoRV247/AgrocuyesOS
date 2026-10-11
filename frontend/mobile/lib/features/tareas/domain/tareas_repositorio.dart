import 'actividad.dart';
import 'tarea_config.dart';

/// Puerto (capa de dominio). El UI y los providers dependen de ESTA firma, no de
/// Drift: es la regla de dependencia apuntando hacia adentro, igual que en el
/// backend (`domain` no conoce `infrastructure`). La implementacion con SQLite
/// esta en `data/tareas_repositorio_local.dart`.
abstract class TareasRepositorio {
  /// Catalogo dinámico reactivo: si el servidor baja una plantilla nueva de
  /// "Aporque", la cuadrilla de botones se redraw sola por este stream.
  Stream<List<TareaConfig>> watchPlantillas();

  Stream<List<ActividadRegistrada>> watchRegistros(String terrenoId);

  /// Alta offline. Genera el UUIDv4 y el `updated_at` absolutos, escribe la
  /// fila y encola el cambio en la MISMA transaccion: no puede existir un
  /// registro guardado que no este en cola de subida.
  Future<ActividadRegistrada> registrar({
    required String terrenoId,
    required TareaConfig plantilla,
    required Map<String, Object?> respuestas,
    String? fechaRealizada,
  });

  /// Edicion LWW: sube `updated_at` y reencola (el payload reemplaza, no
  /// parchea: docs/03).
  Future<ActividadRegistrada> editarMetadata({
    required String id,
    required Map<String, Object?> respuestas,
  });

  /// Borrado logico: tombstone local + cambio `op=delete`. Borrar nunca es
  /// `DELETE FROM`, o el registro resucitaria en el otro dispositivo.
  Future<void> borrar({required String id});
}
