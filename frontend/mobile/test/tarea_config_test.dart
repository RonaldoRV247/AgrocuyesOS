import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:agrocuyes_mobile/features/tareas/domain/tarea_config.dart';

/// Test del contrato dinamico: es la parte de la app que NO necesita Drift ni
/// codegen para verificarse, y es exactamente donde se rompe un catalogo mal
/// formado del server.
void main() {
  const String aporque = '''
{
  "version": 1,
  "ui": {"icono": "aporque", "color": "#A3E635", "orden": 20, "etiqueta_accion": "Guardar aporque"},
  "campos": [
    {"clave": "kg_aplicados", "etiqueta": "Kg aplicados", "tipo": "decimal", "unidad": "kg",
     "min": 0, "max": 500, "paso": 0.5, "default": 2, "obligatorio": true},
    {"clave": "insumo", "etiqueta": "Insumo", "tipo": "seleccion", "obligatorio": true,
     "opciones": [{"valor": "compost", "etiqueta": "Compost"}, {"valor": "cal", "etiqueta": "Cal"}]},
    {"clave": "clima", "etiqueta": "Clima", "tipo": "nube_de_datos_v2"}
  ]
}''';

  test('una plantilla nueva se renderiza sin tocar codigo', () {
    final TareaConfig c =
        TareaConfig.fromMetadataTexto(plantillaId: 'p-1', nombre: 'Aporque', metadataJson: aporque);

    expect(c.icono, 'aporque');
    expect(c.color, 0xFFA3E635);
    expect(c.orden, 20);
    expect(c.etiquetaAccion, 'Guardar aporque');
    expect(c.requiereFormulario, isTrue);
  });

  test('un tipo de campo desconocido se ignora, no tumba la pantalla', () {
    final TareaConfig c =
        TareaConfig.fromMetadataTexto(plantillaId: 'p-1', nombre: 'Aporque', metadataJson: aporque);

    expect(c.campos.length, 3, reason: 'el JSON trae 3 campos');
    expect(c.camposVisibles.length, 2, reason: 'el tipo desconocido no se pinta');
    expect(c.camposVisibles.every((CampoConfig f) => !f.tipo.necesitaTeclado), isTrue,
        reason: 'cero teclados: entero/decimal/seleccion/booleano');
  });

  test('las respuestas se normalizan a escalares tipados antes del JSONB', () {
    final TareaConfig c =
        TareaConfig.fromMetadataTexto(plantillaId: 'p-1', nombre: 'Aporque', metadataJson: aporque);

    final Map<String, Object?> metadata = c.metadataDesde(<String, Object?>{
      'kg_aplicados': '12.5',
      'insumo': 'compost',
      'clima': 'sol',
    });

    expect(jsonDecode(jsonEncode(metadata)), <String, Object?>{
      'kg_aplicados': 12.5,
      'insumo': 'compost',
    }, reason: 'decimal -> double, y la clave del campo ignorable no se escribe');
  });

  test('faltantes: solo los obligatorios del contrato', () {
    final TareaConfig c =
        TareaConfig.fromMetadataTexto(plantillaId: 'p-1', nombre: 'Aporque', metadataJson: aporque);

    expect(c.faltantes(<String, Object?>{}), <String>['kg_aplicados', 'insumo']);
    expect(c.faltantes(<String, Object?>{'kg_aplicados': 2, 'insumo': 'cal'}), isEmpty);
  });

  test('metadata rota conserva el boton y avisa en la UI', () {
    final TareaConfig c =
        TareaConfig.fromMetadataTexto(plantillaId: 'p-1', nombre: 'Riego', metadataJson: '{"ui":[');

    expect(c.configRota, isTrue);
    expect(c.nombre, 'Riego', reason: 'el productor sigue viendo como se llama la tarea');
    expect(c.requiereFormulario, isFalse);
  });

  test('metadata vacia (plantilla legacy sin ui) es registrada con un toque', () {
    final TareaConfig c =
        TareaConfig.fromMetadataTexto(plantillaId: 'p-1', nombre: 'Reviso pozas', metadataJson: '');

    expect(c.configRota, isFalse);
    expect(c.camposVisibles, isEmpty);
    expect(c.icono, 'check_circle');
  });
}
