import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/campo_theme.dart';
import '../../../core/utils/tiempo.dart';
import '../../../core/widgets/estado_vacio.dart';
import '../../sync/application/sync_providers.dart';
import '../application/tareas_providers.dart';
import '../domain/actividad.dart';
import '../domain/tarea_config.dart';
import 'boton_tarea_gigante.dart';
import 'hoja_tarea.dart';

/// ---------------------------------------------------------------------------
/// Renderizador dinamico de tareas: `List<TareaConfig>` (desde
/// `plantilla_proceso.metadata`) -> cuadrilla de botones gigantes. Cero widgets
/// escritos por tipo de proceso.
/// ---------------------------------------------------------------------------
class CuadrillaTareas extends ConsumerWidget {
  const CuadrillaTareas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TareaConfig>> plantillas = ref.watch(plantillasProvider);
    final String? terrenoId = ref.watch(terrenoActivoProvider).valueOrNull;

    return plantillas.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 4)),
      error: (Object e, StackTrace _) => EstadoVacio(
        titulo: 'No se pudo leer el catalogo',
        detalle: 'Reinicia la app. Los registros ya guardados siguen a salvo en el telefono.',
        icono: Icons.error_outline_rounded,
      ),
      data: (List<TareaConfig> lista) {
        if (lista.isEmpty) {
          return const EstadoVacio(
            titulo: 'Sin tareas configuradas',
            detalle: 'Conectate una vez al servidor para bajar el catalogo de procesos.',
            icono: Icons.list_alt_rounded,
          );
        }
        if (terrenoId == null) {
          return const EstadoVacio(
            titulo: 'Sin terreno activo',
            detalle: 'Crea o sincroniza un lote antes de registrar actividades.',
            icono: Icons.agriculture_rounded,
          );
        }

        final List<ActividadRegistrada> hoy =
            ref.watch(registrosDelTerrenoProvider(terrenoId)).valueOrNull ?? const <ActividadRegistrada>[];
        final String fechaHoy = RelojCampo.hoyIso();
        final Map<String, int> vecesHoy = <String, int>{};
        final Set<String> conPendientes = <String>{};
        for (final ActividadRegistrada r in hoy) {
          if (r.fechaRealizada != fechaHoy) continue;
          vecesHoy[r.plantillaId] = (vecesHoy[r.plantillaId] ?? 0) + 1;
          if (r.pendienteDeSync) conPendientes.add(r.plantillaId);
        }

        return RefreshIndicator(
          // En campo el gesto de "jalear" es la unica manera explicita de
          // intentar subir la cola sin esperar al proximo rebrote de senal.
          color: CampoColores.accion,
          backgroundColor: CampoColores.superficie,
          onRefresh: () => ref.read(syncWorkerProvider).sincronizarAhora(),
          child: LayoutBuilder(
            builder: (BuildContext contexto, BoxConstraints c) {
              final int columnas = (c.maxWidth / (kGridTileMin + kGridGap)).floor().clamp(1, 3);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(kGridGap, kGridGap, kGridGap, 120),
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnas,
                  crossAxisSpacing: kGridGap,
                  mainAxisSpacing: kGridGap,
                  mainAxisExtent: kTaskButtonHeight + 38,
                ),
                itemCount: lista.length,
                itemBuilder: (BuildContext _, int i) => BotonTareaGigante(
                  config: lista[i],
                  vecesHoy: vecesHoy[lista[i].plantillaId],
                  pendienteDeSync: conPendientes.contains(lista[i].plantillaId),
                  onTap: () => _registrar(contexto, ref, lista[i], terrenoId),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Ruta corta: una tarea sin campos se registra con UN toque. Las que tienen
  /// campos abren la hoja dinamica.
  Future<void> _registrar(
    BuildContext context,
    WidgetRef ref,
    TareaConfig config,
    String terrenoId,
  ) async {
    if (config.requiereFormulario || config.configRota) {
      await abrirHojaTarea(context: context, config: config, terrenoId: terrenoId);
      return;
    }

    try {
      await ref.read(guardarTareaProvider)(
        terrenoId: terrenoId,
        plantilla: config,
        respuestas: const <String, Object?>{},
      );
      HapticFeedback.heavyImpact();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${config.nombre} guardado. Sube cuando haya senal.'),
            backgroundColor: CampoColores.superficie,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar'),
            backgroundColor: CampoColores.alerta,
          ),
        );
      }
    }
  }
}
