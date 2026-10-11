import 'package:flutter/material.dart';

import '../theme/campo_theme.dart';

/// Estado vacio/error en tamaño campo: texto grande, icono claro, cero botones
/// secundarios. Se usa en la cuadrilla de tareas, la vista de poza y el historial.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.titulo,
    required this.detalle,
    this.icono = Icons.inbox_rounded,
    this.color = CampoColores.textoSecundario,
  });

  final String titulo;
  final String detalle;
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: color),
            const SizedBox(height: 14),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: CampoColores.texto),
            ),
            const SizedBox(height: 8),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, height: 1.35, color: CampoColores.textoSecundario),
            ),
          ],
        ),
      ),
    );
  }
}
