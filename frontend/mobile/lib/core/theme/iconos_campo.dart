import 'package:flutter/material.dart';

/// Catalogo visual: nombre de icono (del JSON del server) -> IconData.
///
/// Es la unica capa que conoce Flutter para las plantillas. El dominio guarda el
/// string, asi el admin puede escribir `"icono": "aporque"` en el catalogo sin
/// que nadie publique una version nueva de la app. Un nombre desconocido cae en
/// [iconoDesconocido] en vez de romper el render.
///
/// Se eligen glifos de trazo grueso: a plena luz del sol un icono de linea fina
/// se convierte en ruido.
IconData resolverIcono(String nombre) => _mapa[nombre] ?? iconoDesconocido;

/// Fallback neutral para tareas sin config o con config rota.
const IconData iconoDesconocido = Icons.help_rounded;

const Map<String, IconData> _mapa = <String, IconData>{
  'check_circle': Icons.check_circle_rounded,
  'help': Icons.help_rounded,
  // -- tareas de cultivo
  'water_drop': Icons.water_drop_rounded,
  'riego': Icons.water_drop_rounded,
  'semilla': Icons.spa_rounded,
  'siembra': Icons.agriculture_rounded,
  'aporque': Icons.grass_rounded,
  'fertilizante': Icons.compost_rounded,
  'insumo': Icons.inventory_2_rounded,
  'cosecha': Icons.eco_rounded,
  'plaga': Icons.bug_report_rounded,
  'maleza': Icons.filter_vintage_rounded,
  'sol': Icons.wb_sunny_rounded,
  'lluvia': Icons.weather_rounded,
  // -- crianza (cuyes)
  'cuy': Icons.pets_rounded,
  'poza': Icons.bia_rounded,
  'monta': Icons.merge_type_rounded,
  'parto': Icons.child_care_rounded,
  'destete': Icons.separator_rounded,
  'vacunacion': Icons.vaccines_rounded,
  'veterinaria': Icons.local_hospital_rounded,
  'muerte': Icons.report_gmailerrorred_rounded,
  'peso': Icons.scale_rounded,
  'comida': Icons.restaurant_rounded,
  'limpieza': Icons.cleaning_services_rounded,
  // -- genericos
  'camara': Icons.photo_camera_rounded,
  'ubicacion': Icons.my_location_rounded,
  'hora': Icons.schedule_rounded,
};
