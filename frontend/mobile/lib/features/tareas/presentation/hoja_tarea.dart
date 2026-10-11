import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/campo_theme.dart';
import '../../../core/widgets/stepper_campo.dart';
import '../application/tareas_providers.dart';
import '../domain/tarea_config.dart';
import 'boton_tarea_gigante.dart';

/// Formulario dinamico de una [TareaConfig]. Se arma campo por campo desde el
/// JSON: nada de esto se escribio para "Siembra" ni para "Vacunacion".
///
/// La regla de diseno: un campo `entero`/`decimal`/`seleccion`/`booleano` NUNCA
/// abre teclado. `texto` existe solo porque el catalogo lo permite; es la
/// excepcion, no el camino.
Future<void> abrirHojaTarea({
  required BuildContext context,
  required TareaConfig config,
  required String terrenoId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: false,
    backgroundColor: CampoColores.fondo,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _HojaTarea(config: config, terrenoId: terrenoId),
  );
}

class _HojaTarea extends ConsumerStatefulWidget {
  const _HojaTarea({required this.config, required this.terrenoId});

  final TareaConfig config;
  final String terrenoId;

  @override
  ConsumerState<_HojaTarea> createState() => _HojaTareaState();
}

class _HojaTareaState extends ConsumerState<_HojaTarea> {
  final Map<String, Object?> _respuestas = <String, Object?>{};
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Un default por campo: en campo se registra lo habitual y se ajustan dos
    // toques, no se escribe desde cero.
    for (final CampoConfig c in widget.config.camposVisibles) {
      if (c.valorPorDefecto != null) _respuestas[c.clave] = c.valorPorDefecto;
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await ref.read(guardarTareaProvider)(
        terrenoId: widget.terrenoId,
        plantilla: widget.config,
        respuestas: _respuestas,
      );
      // Vibracion fuerte = "guardado", para no depender de leer un toast bajo
      // el sol. El pop y el aviso van despues del feedback.
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      Navigator.of(context).pop();
      _aviso('${widget.config.nombre} registrado. Se sube cuando vuelva la señal.');
    } on FaltaCampoException catch (e) {
      if (mounted) _aviso('Falta: ${e.claves.join(', ')}', alerta: true);
    } catch (_) {
      if (mounted) _aviso('No se pudo guardar. Intenta de nuevo.', alerta: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _aviso(String texto, {bool alerta = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: alerta ? CampoColores.alerta : CampoColores.superficie,
      ),
    );
  }

  num _valorNum(String clave, num defecto) {
    final Object? v = _respuestas[clave];
    if (v is num) return v;
    return num.tryParse('$v') ?? defecto;
  }

  @override
  Widget build(BuildContext context) {
    final List<CampoConfig> campos = widget.config.camposVisibles;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.config.nombre.toUpperCase(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            if (widget.config.configRota)
              const Text(
                'Configuracion de esta tarea no se entiende. Se puede registrar sin detalles.',
                style: TextStyle(color: CampoColores.pendienteDeSync),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: campos.map(_campo).toList()),
              ),
            ),
            const SizedBox(height: 12),
            // Confirmar: el boton mas grande de la pantalla despues del de la
            // cuadrilla, y abajo del todo (zona del pulgar).
            SizedBox(
              height: kTaskButtonHeight - 20,
              child: ElevatedButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: const Icon(Icons.check_rounded, size: 34),
                label: Text(widget.config.etiquetaAccion),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(CampoConfig c) {
    switch (c.tipo) {
      case CampoTipo.entero:
        return StepperCampo(
          etiqueta: c.etiqueta,
          unidad: c.unidad,
          min: c.min,
          max: c.max,
          paso: c.paso,
          valor: _valorNum(c.clave, c.min),
          onChanged: (num v) => setState(() => _respuestas[c.clave] = v.toInt()),
        );

      case CampoTipo.decimal:
        return StepperCampo(
          etiqueta: c.etiqueta,
          unidad: c.unidad,
          min: c.min,
          max: c.max,
          paso: c.paso,
          decimales: 1,
          valor: _valorNum(c.clave, c.min),
          onChanged: (num v) => setState(() => _respuestas[c.clave] = v.toDouble()),
        );

      case CampoTipo.seleccion:
        final String? actual = _respuestas[c.clave] == null ? null : '${_respuestas[c.clave]}';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.etiqueta.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: CampoColores.textoSecundario)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: c.opciones.map((o) {
                  final bool elegido = actual == o.valor;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _respuestas[c.clave] = o.valor);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      // Minimo 60dp de alto: un token de seleccion tambien es
                      // un boton, no un label chic.
                      constraints: const BoxConstraints(minHeight: kTouchMin, minWidth: 96),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: elegido ? CampoColores.accion : CampoColores.superficie,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: CampoColores.borde, width: 2),
                      ),
                      child: Text(
                        o.etiqueta,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: elegido ? CampoColores.sobreAccion : CampoColores.texto,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );

      case CampoTipo.booleano:
        final Object? v = _respuestas[c.clave];
        final bool? actual = v == null ? null : (v == true || '$v' == 'true');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(c.etiqueta, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              _BotonSiNo(
                texto: 'NO',
                activo: actual == false,
                color: CampoColores.alerta,
                onTap: () => setState(() => _respuestas[c.clave] = false),
              ),
              const SizedBox(width: 10),
              _BotonSiNo(
                texto: 'SI',
                activo: actual == true,
                color: CampoColores.accion,
                onTap: () => setState(() => _respuestas[c.clave] = true),
              ),
            ],
          ),
        );

      case CampoTipo.texto:
        // Escape hatch del catalogo: unico caso donde aparece el teclado.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            onChanged: (String v) => _respuestas[c.clave] = v,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              labelText: c.etiqueta,
              suffixText: c.unidad,
              border: const OutlineInputBorder(),
            ),
          ),
        );

      case CampoTipo.desconocido:
        return const SizedBox.shrink();
    }
  }
}

class _BotonSiNo extends StatelessWidget {
  const _BotonSiNo({required this.texto, required this.activo, required this.color, required this.onTap});

  final String texto;
  final bool activo;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: kTouchDefault, minWidth: 84),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: activo ? color : CampoColores.superficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: activo ? color : CampoColores.borde, width: 2),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: activo ? BotonTareaGigante.frentePara(color) : CampoColores.texto,
          ),
        ),
      ),
    );
  }
}

