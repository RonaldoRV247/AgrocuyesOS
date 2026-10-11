import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/campo_theme.dart';
import '../../../core/theme/iconos_campo.dart';
import '../../../core/widgets/estado_vacio.dart';
import '../../../core/widgets/stepper_campo.dart';
import '../../../shared/data/local/app_database.dart';
import '../data/crianza_repositorio.dart';
import '../application/crianza_providers.dart';

/// ---------------------------------------------------------------------------
/// Vista de Poza (cuyes). Disenada alrededor de dos gestos: +/- de mortandad y
/// +/- de nacimientos. Sin teclado, sin formularios, con los numeros en 44px.
///
/// El borrador (cuantas murieron / cuantas nacieron) se acumula en memoria y se
/// confirma con UN boton: cada toque al stepper no escribe en la base de datos,
/// porque 30 toques = 30 transacciones = 30 cambios encolados = 30 requests.
/// ---------------------------------------------------------------------------
class VistaPozas extends ConsumerStatefulWidget {
  const VistaPozas({super.key});

  @override
  ConsumerState<VistaPozas> createState() => _VistaPozasState();
}

class _VistaPozasState extends ConsumerState<VistaPozas> {
  String? _pozaId;
  CampoPoza _grupo = CampoPoza.crias;
  int _mortandad = 0;
  int _nacimientos = 0;

  void _seleccionarPoza(String id) {
    // Cambiar de poza descarta el borrador: si no, se le atribuyen muertes a
    // la poza equivocada, y eso es exactamente el dato que nadie detecta.
    setState(() {
      _pozaId = id;
      _mortandad = 0;
      _nacimientos = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? galponId = ref.watch(galponActivoProvider).valueOrNull;

    if (galponId == null) {
      return const EstadoVacio(
        titulo: 'Sin galpon',
        detalle: 'Sincroniza una vez para bajar tus galpones y pozas.',
        icono: Icons.home_rounded,
      );
    }

    final List<PozaRow> pozas = ref.watch(pozasDelGalponProvider(galponId)).valueOrNull ?? const <PozaRow>[];
    if (pozas.isEmpty) {
      return const EstadoVacio(
        titulo: 'Sin pozas en este galpon',
        detalle: 'Crea las pozas desde la web o pide el catalogo al tecnico.',
        icono: Icons.pets_rounded,
      );
    }

    final PozaRow poza = pozas.firstWhere(
      (PozaRow p) => p.id == _pozaId,
      orElse: () => pozas.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selector de poza: chips de 60dp, deslizable. Cero dropdowns (un
        // dropdown en pleno sol es una trampa).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: kGridGap, vertical: 8),
          child: Row(
            children: pozas
                .map((PozaRow p) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () => _seleccionarPoza(p.id),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: kTouchMin, minWidth: 76),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            color: p.id == poza.id ? CampoColores.accion : CampoColores.superficie,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CampoColores.borde, width: 2),
                          ),
                          child: Text(
                            p.codigo,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: p.id == poza.id ? CampoColores.sobreAccion : CampoColores.texto,
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(kGridGap, 4, kGridGap, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Inventario(poza: poza),
                const Divider(color: CampoColores.borde, height: 28),
                StepperCampo(
                  etiqueta: 'Mortandad',
                  valor: _mortandad,
                  max: 50,
                  acento: CampoColores.alerta,
                  onChanged: (num v) => setState(() => _mortandad = v.toInt()),
                ),
                _GruposAfectados(seleccionado: _grupo, onElegir: (c) => setState(() => _grupo = c)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _mortandad == 0 ? null : () => _confirmarMortalidad(poza),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CampoColores.alerta,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.report_gmailerrorred_rounded, size: 32),
                  label: Text('Registrar $_mortandad muerte(s)'),
                ),
                const SizedBox(height: 22),
                StepperCampo(
                  etiqueta: 'Nacimientos',
                  valor: _nacimientos,
                  max: 20,
                  onChanged: (num v) => setState(() => _nacimientos = v.toInt()),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _nacimientos == 0 ? null : () => _confirmarNacimientos(poza),
                  icon: const Icon(Icons.child_care_rounded, size: 32),
                  label: Text('Registrar $_nacimientos cria(s) nueva(s)'),
                ),
                const SizedBox(height: 22),
                _HistorialEventos(pozaId: poza.id),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmarMortalidad(PozaRow poza) async {
    final CrianzaRepositorio repo = ref.read(crianzaRepositorioProvider);
    try {
      await repo.registrarMortalidad(pozaId: poza.id, cantidad: _mortandad, campo: _grupo);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() => _mortandad = 0);
      _aviso('Mortandad registrada en ${poza.codigo}');
    } catch (_) {
      if (mounted) _aviso('No se pudo registrar', alerta: true);
    }
  }

  Future<void> _confirmarNacimientos(PozaRow poza) async {
    final CrianzaRepositorio repo = ref.read(crianzaRepositorioProvider);
    try {
      await repo.registrarNacimientos(pozaId: poza.id, cantidad: _nacimientos);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() => _nacimientos = 0);
      _aviso('Parto registrado en ${poza.codigo}');
    } catch (_) {
      if (mounted) _aviso('No se pudo registrar', alerta: true);
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
}

class _Inventario extends StatelessWidget {
  const _Inventario({required this.poza});

  final PozaRow poza;

  @override
  Widget build(BuildContext context) {
    final int total = poza.hembras + poza.machos + poza.crias;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Poza ${poza.codigo}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            if (poza.sincronizadoEn == null)
              const Icon(Icons.cloud_upload_rounded, color: CampoColores.pendienteDeSync, size: 26),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Cifra(cantidad: total, etiqueta: 'total'),
            _Cifra(cantidad: poza.hembras, etiqueta: 'hembras'),
            _Cifra(cantidad: poza.machos, etiqueta: 'machos'),
            _Cifra(cantidad: poza.crias, etiqueta: 'crias'),
          ],
        ),
      ],
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.cantidad, required this.etiqueta});

  final int cantidad;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$cantidad', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
          Text(
            etiqueta.toUpperCase(),
            style: const TextStyle(fontSize: 13, letterSpacing: 1, color: CampoColores.textoSecundario),
          ),
        ],
      ),
    );
  }
}

class _GruposAfectados extends StatelessWidget {
  const _GruposAfectados({required this.seleccionado, required this.onElegir});

  final CampoPoza seleccionado;
  final ValueChanged<CampoPoza> onElegir;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: CampoPoza.values
          .map((CampoPoza c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => onElegir(c),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: kTouchMin),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: c == seleccionado ? CampoColores.alerta : CampoColores.superficie,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: CampoColores.borde, width: 2),
                      ),
                      child: Text(
                        c.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: c == seleccionado ? Colors.white : CampoColores.textoSecundario,
                        ),
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _HistorialEventos extends ConsumerWidget {
  const _HistorialEventos({required this.pozaId});

  final String pozaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<EventoPozaRow> eventos =
        ref.watch(eventosDePozaProvider(pozaId)).valueOrNull ?? const <EventoPozaRow>[];

    if (eventos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Aun sin eventos en esta poza', style: TextStyle(fontSize: 18, color: CampoColores.textoSecundario)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('LO QUE PASO AQUI',
            style: TextStyle(fontSize: 15, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: CampoColores.textoSecundario)),
        const SizedBox(height: 8),
        ...eventos.take(8).map((EventoPozaRow e) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CampoColores.superficie,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CampoColores.borde),
              ),
              child: Row(
                children: [
                  Icon(resolverIcono(e.tipoEvento.toLowerCase()), size: 28, color: CampoColores.texto),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.tipoEvento, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        Text('${e.fechaEvento} · ${_resumen(e.detalles)}',
                            style: const TextStyle(fontSize: 15, color: CampoColores.textoSecundario)),
                      ],
                    ),
                  ),
                  if (e.sincronizadoEn == null)
                    const Icon(Icons.cloud_upload_rounded, size: 20, color: CampoColores.pendienteDeSync),
                ],
              ),
            )),
      ],
    );
  }

  String _resumen(String detallesJson) {
    try {
      final Object? d = jsonDecode(detallesJson.isEmpty ? '{}' : detallesJson);
      if (d is! Map) return 'Sin detalles';
      return d.entries.map((e) => '${e.value}').join(' · ');
    } catch (_) {
      return 'Sin detalles';
    }
  }
}
