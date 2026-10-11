import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/campo_theme.dart';

/// Contador +/- de campo. Cero teclado: la mortandad, los nacimientos y los
/// kilos aplicados se ajustan tocando dos circulos de [kStepperButton] dp.
///
/// Sirve igual para enteros (`decimales: null`: cabezas de cuy) que para
/// decimales (`decimales: 1`, `paso: 0.5`: kg de insumo), porque el JSON de la
/// plantilla define la granularidad y el widget no lo sabe.
///
/// Comportamiento pensado para mano ocupada:
///  * toque simple  -> un paso
///  * mantener      -> aceleracion (primer paso a los 400ms, luego cada 110ms)
///  * cada paso     -> vibracion ligera, para confirmar sin mirar la pantalla
///  * el valor va en el centro, en 44px, y repetido en semantics
class StepperCampo extends StatefulWidget {
  const StepperCampo({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onChanged,
    this.min = 0,
    this.max = 9999,
    this.paso = 1,
    this.unidad,
    this.decimales,
    this.acento = CampoColores.accion,
  });

  final String etiqueta;
  final num valor;
  final ValueChanged<num> onChanged;
  final num min;
  final num max;
  final num paso;
  final String? unidad;

  /// Null => se muestra como entero (mortandad, nacimientos).
  final int? decimales;
  final Color acento;

  @override
  State<StepperCampo> createState() => _StepperCampoState();
}

class _StepperCampoState extends State<StepperCampo> {
  Timer? _arranque;
  Timer? _repeticion;
  bool _repitiendo = false;

  @override
  void dispose() {
    _arranque?.cancel();
    _repeticion?.cancel();
    super.dispose();
  }

  String _formatear(num v) {
    final int? decimales = widget.decimales;
    return decimales == null ? '${v.toInt()}' : v.toStringAsFixed(decimales);
  }

  void _aplicar(int signo) {
    final num destino = (widget.valor + signo * widget.paso).clamp(widget.min, widget.max);
    if (destino == widget.valor) return;
    HapticFeedback.lightImpact();
    widget.onChanged(destino);
  }

  void _presionar(int signo) {
    _repitiendo = false;
    _arranque?.cancel();
    _repeticion?.cancel();
    _arranque = Timer(const Duration(milliseconds: 400), () {
      _repitiendo = true;
      _aplicar(signo);
      _repeticion = Timer.periodic(const Duration(milliseconds: 110), (_) => _aplicar(signo));
    });
  }

  void _soltar(int signo) {
    _arranque?.cancel();
    _repeticion?.cancel();
    // Si no llego a activarse el modo mantener, fue un toque normal.
    if (!_repitiendo) _aplicar(signo);
    _repitiendo = false;
  }

  void _cancelar() {
    _arranque?.cancel();
    _repeticion?.cancel();
    _repitiendo = false;
  }

  Widget _boton({required IconData icono, required int signo, required Color color}) {
    return GestureDetector(
      onTapDown: (_) => _presionar(signo),
      onTapUp: (_) => _soltar(signo),
      onTapCancel: _cancelar,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: '${signo > 0 ? "Aumentar" : "Disminuir"} ${widget.etiqueta}',
        child: Container(
          width: kStepperButton,
          height: kStepperButton,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(icono, size: 40, color: CampoColores.sobreAccion),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.etiqueta.toUpperCase(),
            style: const TextStyle(
              fontSize: 16,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: CampoColores.textoSecundario,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _boton(icono: Icons.remove_rounded, signo: -1, color: CampoColores.superficie),
              Semantics(
                value: '${_formatear(widget.valor)} ${widget.unidad ?? widget.etiqueta}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatear(widget.valor),
                      style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: widget.acento),
                    ),
                    if (widget.unidad != null)
                      Text(widget.unidad!,
                          style: const TextStyle(fontSize: 16, color: CampoColores.textoSecundario)),
                  ],
                ),
              ),
              _boton(icono: Icons.add_rounded, signo: 1, color: widget.acento),
            ],
          ),
        ],
      ),
    );
  }
}
