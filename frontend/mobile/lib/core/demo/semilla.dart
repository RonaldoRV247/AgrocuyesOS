import 'dart:convert';

import 'package:drift/drift.dart';

import '../shared/data/local/app_database.dart';
import '../utils/tiempo.dart';

/// ---------------------------------------------------------------------------
/// Datos de arranque para poder correr la app SIN server (modo campo recien
/// instalado). Son exactamente el tipo de filas que llegarian por pull delta,
/// y sirven para probar el renderizador dinamico: las tres tareas de abajo son
/// puras lineas de `metadata`, ninguna tiene una pantalla escrita a medida.
///
/// En produccion esto se reemplaza por la bajada del catalogo; se mantiene
/// detras de un guardado para no pisar nunca datos reales del productor.
/// ---------------------------------------------------------------------------
Future<void> sembrarSiVacio(AppDatabase db, RelojCampo reloj) async {
  final List<PlantillaProcesoRow> plantillas = await db.select(db.plantillaProceso).get();
  if (plantillas.isNotEmpty) return;

  final int ahora = reloj.ahoraMillis();
  final String terrenoId = nuevoUuidV4();
  final String galponId = nuevoUuidV4();

  await db.upsertTerreno(
    TerrenoCompanion.insert(
      id: terrenoId,
      nombre: 'Lote familiar La Pampa',
      areaM2: const Value(1250.0),
      createdAt: ahora,
      updatedAt: ahora,
    ),
  );

  await db.upsertGalpon(
    GalponCompanion.insert(id: galponId, nombre: 'Galpon 1', capacidadMaxima: const Value(120), createdAt: ahora, updatedAt: ahora),
  );

  for (final List<Object?> p in <List<Object?>>[
    <Object?>['P-01', 18, 3, 12],
    <Object?>['P-02', 14, 2, 7],
  ]) {
    await db.upsertPoza(
      PozaCompanion.insert(
        id: nuevoUuidV4(),
        galponId: galponId,
        codigo: p[0]! as String,
        hembras: Value(p[1]! as int),
        machos: Value(p[2]! as int),
        crias: Value(p[3]! as int),
        createdAt: ahora,
        updatedAt: ahora,
      ),
    );
  }

  // Catalogo dinamico: agregar "Aporque" o "Vacunacion" es INSERT, no deploy.
  for (final Map<String, Object?> plantilla in <Map<String, Object?>>[
    <String, Object?>{
      'nombre': 'Riego',
      'metadata': <String, Object?>{
        'version': 1,
        'ui': <String, Object?>{'icono': 'water_drop', 'color': '#22C55E', 'orden': 10, 'etiqueta_accion': 'Guardar riego'},
        'campos': <Object?>[
          <String, Object?>{
            'clave': 'minutos_riego',
            'etiqueta': 'Minutos de riego',
            'tipo': 'entero',
            'unidad': 'min',
            'min': 0,
            'max': 240,
            'paso': 5,
            'default': 10,
            'obligatorio': true,
          },
          <String, Object?>{'clave': 'suelo_humedo', 'etiqueta': 'Salo aun humedo?', 'tipo': 'booleano'},
        ],
      },
    },
    <String, Object?>{
      'nombre': 'Aporque',
      'metadata': <String, Object?>{
        'version': 1,
        'ui': <String, Object?>{'icono': 'aporque', 'color': '#A3E635', 'orden': 20, 'etiqueta_accion': 'Guardar aporque'},
        'campos': <Object?>[
          <String, Object?>{
            'clave': 'kg_aplicados',
            'etiqueta': 'Kg aplicados',
            'tipo': 'decimal',
            'unidad': 'kg',
            'min': 0,
            'max': 500,
            'paso': 0.5,
            'default': 2,
            'obligatorio': true,
          },
          <String, Object?>{
            'clave': 'insumo',
            'etiqueta': 'Insumo',
            'tipo': 'seleccion',
            'obligatorio': true,
            'opciones': <Object?>[
              <String, Object?>{'valor': 'compost', 'etiqueta': 'Compost'},
              <String, Object?>{'valor': 'gallinaza', 'etiqueta': 'Gallinaza'},
              <String, Object?>{'valor': 'cal', 'etiqueta': 'Cal'},
            ],
          },
        ],
      },
    },
    <String, Object?>{
      'nombre': 'Vacunacion',
      'metadata': <String, Object?>{
        'version': 1,
        'dominio': 'crianza',
        'ui': <String, Object?>{'icono': 'vacunacion', 'color': '#38BDF8', 'orden': 30, 'etiqueta_accion': 'Guardar vacunacion'},
        'campos': <Object?>[
          <String, Object?>{'clave': 'dosis_ml', 'etiqueta': 'Dosis', 'tipo': 'decimal', 'unidad': 'ml', 'min': 0, 'max': 10, 'paso': 0.5, 'default': 1},
          <String, Object?>{'clave': 'lote_laboratorio', 'etiqueta': 'Lote del laboratorio', 'tipo': 'texto'},
        ],
      },
    },
    <String, Object?>{
      // Sin `campos`: se registra con UN toque (el boton rapido de la cuadrilla).
      'nombre': 'Reviso pozas',
      'metadata': <String, Object?>{
        'version': 1,
        'ui': <String, Object?>{'icono': 'cuy', 'color': '#F59E0B', 'orden': 40, 'etiqueta_accion': 'Listo'},
      },
    },
  ]) {
    await db.upsertPlantilla(
      PlantillaProcesoCompanion.insert(
        id: nuevoUuidV4(),
        nombre: plantilla['nombre']! as String,
        metadata: Value(jsonEncode(plantilla['metadata'])),
        createdAt: ahora,
        updatedAt: ahora,
      ),
    );
  }
}
