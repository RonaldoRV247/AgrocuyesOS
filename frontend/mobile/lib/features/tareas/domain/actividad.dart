/// Vista de dominio de un registro ya guardado. Se construye a partir de la fila
/// de Drift parseando `metadata`: la UI nunca ve JSON crudo ni columnas.
class ActividadRegistrada {
  const ActividadRegistrada({
    required this.id,
    required this.terrenoId,
    required this.plantillaId,
    required this.plantillaNombre,
    required this.fechaRealizada,
    required this.metadata,
    required this.updatedAt,
    this.sincronizadoEn,
  });

  /// El mismo UUIDv4 que el server conoce como `id` y como `client_uuid`.
  final String id;
  final String terrenoId;
  final String plantillaId;
  final String plantillaNombre;

  /// `yyyy-MM-dd` local del productor.
  final String fechaRealizada;

  /// Datos dinamicos: las claves que definió la plantilla de la tarea.
  final Map<String, Object?> metadata;

  /// Timestamp LWW absoluto de esta version.
  final int updatedAt;

  /// Null => todavia no subio. La UI lo pinta con el badge ambar "sin sync".
  final int? sincronizadoEn;

  bool get pendienteDeSync => sincronizadoEn == null;

  /// Resumen para la tarjeta de historial: "12 kg · humedad 18%" sin hardcodear
  /// ninguna clave, porque el catalogo es del usuario.
  String get resumen {
    if (metadata.isEmpty) return 'Sin detalles';
    return metadata.entries
        .take(3)
        .map((e) => '${e.value} ${e.key.replaceAll('_', ' ')}'.trim())
        .join(' · ');
  }

  @override
  String toString() => 'ActividadRegistrada($id, $plantillaNombre, $fechaRealizada)';
}
