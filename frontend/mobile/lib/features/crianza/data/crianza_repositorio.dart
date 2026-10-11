import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/utils/tiempo.dart';
import '../../../shared/data/local/app_database.dart';

/// Inventario que se ajusta con los +/- de la pantalla.
enum CampoPoza { hembras, machos, crias }

/// ---------------------------------------------------------------------------
/// Core de crianza. Dos cosas distintas y no conviene mezclarlas:
///
///  * `poza.hembras/machos/crias` es el INVENTARIO: un cache que la pantalla
///    muestra y edita.
///  * `evento_poza` es el HECHO historico (Mortalidad, Parto, Vacunacion...) con
///    sus `detalles` dinamicos.
///
/// Los dos se escriben en la MISMA transaccion y los dos se encolan: si el
/// inventario sube y el evento no, el server ve numeros sin explicacion. Y el
/// `tipo_evento` es TEXT libre: "Vacunacion" es una fila, no un caso en un
/// switch.
/// ---------------------------------------------------------------------------
class CrianzaRepositorio {
  CrianzaRepositorio(this._db, this._reloj);

  final AppDatabase _db;
  final RelojCampo _reloj;

  /// Mortandad: baja del grupo elegido y deja el evento con la cantidad real
  /// aplicada (un delta que se iba a negativo se recorta a 0, no se pierde).
  Future<void> registrarMortalidad({
    required String pozaId,
    required int cantidad,
    required CampoPoza campo,
  }) async {
    if (cantidad <= 0) return;
    final PozaRow? poza = await _db.buscarPoza(pozaId);
    if (poza == null) throw StateError('poza inexistente: $pozaId');

    final int antes = _leer(poza, campo);
    final int despues = (antes - cantidad).clamp(0, antes);
    final int aplicado = antes - despues;
    if (aplicado <= 0) return;

    await _modificarInventario(
      poza: poza,
      campo: campo,
      nuevoValor: despues,
      tipoEvento: 'Mortalidad',
      detalles: <String, Object?>{'cantidad': aplicado, 'campo_afectado': campo.name},
    );
  }

  /// Nacimientos: suben las crias y generan el evento `Parto` con
  /// `numero_crias`, la clave que ya usa el backend en sus ejemplos de JSONB.
  Future<void> registrarNacimientos({required String pozaId, required int cantidad}) async {
    if (cantidad <= 0) return;
    final PozaRow? poza = await _db.buscarPoza(pozaId);
    if (poza == null) throw StateError('poza inexistente: $pozaId');

    await _modificarInventario(
      poza: poza,
      campo: CampoPoza.crias,
      nuevoValor: poza.crias + cantidad,
      tipoEvento: 'Parto',
      detalles: <String, Object?>{'numero_crias': cantidad},
    );
  }

  /// Evento del catalogo dinamico que NO mueve inventario: Vacunacion,
  /// Desparasitacion, Limpieza... Es el punto de entrada para que una plantilla
  /// con `dominio: "crianza"` se renderice aqui sin publicar codigo nuevo.
  Future<void> registrarEvento({
    required String pozaId,
    required String tipoEvento,
    required Map<String, Object?> detalles,
    String? fechaEvento,
  }) async {
    final int ahora = _reloj.ahoraMillis();
    final String fecha = fechaEvento ?? RelojCampo.hoyIso();
    await _insertarEvento(pozaId: pozaId, tipoEvento: tipoEvento, detalles: detalles, ahora: ahora, fecha: fecha);
  }

  Future<void> _modificarInventario({
    required PozaRow poza,
    required CampoPoza campo,
    required int nuevoValor,
    required String tipoEvento,
    required Map<String, Object?> detalles,
    String? fechaEvento,
  }) async {
    final int ahora = _reloj.ahoraMillis();
    final String fecha = fechaEvento ?? RelojCampo.hoyIso();

    final int hembras = campo == CampoPoza.hembras ? nuevoValor : poza.hembras;
    final int machos = campo == CampoPoza.machos ? nuevoValor : poza.machos;
    final int crias = campo == CampoPoza.crias ? nuevoValor : poza.crias;

    await _db.transaction(() async {
      await _db.upsertPoza(
        PozaCompanion(
          id: Value(poza.id),
          galponId: Value(poza.galponId),
          codigo: Value(poza.codigo),
          hembras: Value(hembras),
          machos: Value(machos),
          crias: Value(crias),
          createdAt: Value(poza.createdAt),
          updatedAt: Value(ahora),
          deleted: Value(poza.deleted),
          deletedAt: Value(poza.deletedAt),
          sincronizadoEn: const Value(null),
        ),
      );
      await _db.encolar(
        entity: Entidades.poza,
        recordId: poza.id,
        payload: jsonEncode(<String, Object?>{
          'galpon_id': poza.galponId,
          'codigo': poza.codigo,
          'hembras': hembras,
          'machos': machos,
          'crias': crias,
        }),
        updatedAt: ahora,
      );
      await _insertarEvento(pozaId: poza.id, tipoEvento: tipoEvento, detalles: detalles, ahora: ahora, fecha: fecha);
    });
  }

  Future<void> _insertarEvento({
    required String pozaId,
    required String tipoEvento,
    required Map<String, Object?> detalles,
    required int ahora,
    required String fecha,
  }) async {
    final String id = nuevoUuidV4();
    await _db.upsertEventoPoza(
      EventoPozaCompanion.insert(
        id: id,
        pozaId: pozaId,
        tipoEvento: tipoEvento,
        fechaEvento: fecha,
        detalles: Value(jsonEncode(detalles)),
        createdAt: ahora,
        updatedAt: ahora,
      ),
    );
    await _db.encolar(
      entity: Entidades.eventoPoza,
      recordId: id,
      payload: jsonEncode(<String, Object?>{
        'poza_id': pozaId,
        'tipo_evento': tipoEvento,
        'fecha_evento': fecha,
        'detalles': detalles,
      }),
      updatedAt: ahora,
    );
  }

  int _leer(PozaRow p, CampoPoza campo) => switch (campo) {
        CampoPoza.hembras => p.hembras,
        CampoPoza.machos => p.machos,
        CampoPoza.crias => p.crias,
      };
}
