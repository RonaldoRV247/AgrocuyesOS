import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/data/local/app_database.dart';
import '../../../shared/di/inyeccion.dart';
import '../data/crianza_repositorio.dart';

final crianzaRepositorioProvider = Provider<CrianzaRepositorio>((ref) =>
    CrianzaRepositorio(ref.watch(baseDeDatosProvider), ref.watch(relojProvider)));

final galponActivoProvider = FutureProvider<String?>((ref) async {
  final List<GalponRow> galpones = await ref.watch(baseDeDatosProvider).traerGalponesActivos();
  return galpones.isEmpty ? null : galpones.first.id;
});

/// Pozas del galpon, reactivas: un alta desde la web aparece solita en cuanto
/// entra por pull delta.
final pozasDelGalponProvider = StreamProvider.family<List<PozaRow>, String>(
  (ref, galponId) => ref.watch(baseDeDatosProvider).watchPozasDeGalpon(galponId),
);

final eventosDePozaProvider = StreamProvider.family<List<EventoPozaRow>, String>(
  (ref, pozaId) => ref.watch(baseDeDatosProvider).watchEventosDePoza(pozaId),
);
