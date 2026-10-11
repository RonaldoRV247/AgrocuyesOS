import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/campo_theme.dart';
import '../../../core/theme/iconos_campo.dart';
import '../domain/tarea_config.dart';

/// ---------------------------------------------------------------------------
/// Boton gigante generado 100% por dato. Recibe un [TareaConfig] (el JSON de
/// "Configuracion de Tarea" del server) y de ahi salen el icono, el color, el
/// texto y el numero de pasos. Agregar "Aporque" o "Vacunacion" no toca este
/// archivo.
///
/// Geometria: altura minima [kTaskButtonHeight] (112dp) sobre un tile de
/// [kGridTileMin] dp de ancho. El area tocable real es 2x el minimo exigido de
/// 60dp, que es lo que hace falta con guantes y una mano.
/// ---------------------------------------------------------------------------
class BotonTareaGigante extends StatelessWidget {
  const BotonTareaGigante({
    super.key,
    required this.config,
    this.onTap,
    this.vecesHoy,
    this.pendienteDeSync = false,
  });

  final TareaConfig config;
  final VoidCallback? onTap;

  /// Cuantas veces se registro hoy: evita repetir la misma labor dos veces.
  final int? vecesHoy;

  /// True si la ultima tarea de este tipo aun no subio (punto ambar).
  final bool pendienteDeSync;

  /// El server manda colores arbitrarios. En vez de confiar, se elige el
  /// foreground por luminancia: sobre amarillo va texto oscuro y sobre verde
  /// intenso texto claro. Con esto el contraste AA+ se mantiene para CUALQUIER
  /// plantilla nueva, sin revisarla a mano.
  static Color frentePara(Color base) =>
      base.computeLuminance() > 0.45 ? const Color(0xFF06130A) : const Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final Color base = Color(config.color);
    final Color frente = frentePara(base);
    final bool deshabilitado = onTap == null;
    final IconData icono = config.configRota ? iconoDesconocido : resolverIcono(config.icono);

    return Semantics(
      button: true,
      enabled: !deshabilitado,
      label: '${config.etiquetaAccion}. '
          '${config.requiereFormulario ? "${config.camposVisibles.length} datos por registrar" : "un toque"}'
          '${(vecesHoy ?? 0) > 0 ? '. Ya lo hiciste ${vecesHoy} veces hoy' : ''}',
      child: Opacity(
        opacity: deshabilitado ? 0.4 : 1,
        child: Material(
          color: base,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    // Confirmacion tactil: el productor sigue trabajando sin
                    // mirar la pantalla.
                    HapticFeedback.mediumImpact();
                    onTap!.call();
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              constraints: const BoxConstraints(minHeight: kTaskButtonHeight),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: frente.withOpacity(0.22), width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icono, size: 42, color: frente),
                      const Spacer(),
                      if ((vecesHoy ?? 0) > 0) _Contador(valor: vecesHoy!, frente: frente),
                      if (pendienteDeSync)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.cloud_upload_rounded, size: 22, color: CampoColores.pendienteDeSync),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    config.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: frente, height: 1.1),
                  ),
                  Text(
                    config.requiereFormulario
                        ? '${config.camposVisibles.length} dato(s)'
                        : 'un solo toque',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: frente.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({required this.valor, required this.frente});

  final int valor;
  final Color frente;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: frente.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$valor hoy',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: frente),
      ),
    );
  }
}
