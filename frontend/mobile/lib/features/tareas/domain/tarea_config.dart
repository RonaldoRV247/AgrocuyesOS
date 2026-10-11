import 'dart:convert';

/// ---------------------------------------------------------------------------
/// Configuracion de Tarea = `plantilla_proceso.metadata` (JSONB del server,
/// TEXT en SQLite). Todo lo que hace falta para dibujar un boton y su
/// formulario viene AQUI, como dato: "Aporque", "Vacunacion" o el proceso que
/// el productor invente manana no existe en codigo.
///
/// Contrato esperado (versionado, porque un JSON sin version no se puede
/// validar ni hacer evolucionar):
///
/// ```jsonc
/// {
///   "version": 1,
///   "ui": { "icono": "water_drop", "color": "#22C55E", "orden": 10,
///           "etiqueta_accion": "Registrar riego" },
///   "campos": [
///     { "clave": "minutos_riego", "etiqueta": "Minutos", "tipo": "entero",
///       "unidad": "min", "min": 0, "max": 240, "paso": 5, "obligatorio": true },
///     { "clave": "insumo", "etiqueta": "Insumo", "tipo": "seleccion",
///       "opciones": [ {"valor": "compost", "etiqueta": "Compost"} ] },
///     { "clave": "lote_revisado", "etiqueta": "Reviso el lote", "tipo": "booleano" }
///   ]
/// }
/// ```
///
/// Los tipos validos son los de [CampoTipo]: `entero` y `seleccion` se pintan
/// con stepper/tokens, o sea SIN teclado. `texto` existe solo como escape hatch.
/// ---------------------------------------------------------------------------
enum CampoTipo {
  entero,
  decimal,
  seleccion,
  booleano,
  texto,
  desconocido;

  /// Catalogo abierto: un nombre nuevo (por ejemplo uno generado por un modelo)
  /// NO revienta la pantalla, cae en [desconocido] y se omite del formulario.
  static CampoTipo desdeNombre(String? nombre) {
    return switch (nombre) {
      'entero' || 'contador' || 'stepper' || 'int' => CampoTipo.entero,
      'decimal' || 'numero' || 'double' => CampoTipo.decimal,
      'seleccion' || 'opcion' || 'enumeracion' => CampoTipo.seleccion,
      'booleano' || 'si_no' || 'switch' => CampoTipo.booleano,
      'texto' || 'string' => CampoTipo.texto,
      _ => CampoTipo.desconocido,
    };
  }

  bool get necesitaTeclado => this == CampoTipo.texto;
}

class OpcionConfig {
  const OpcionConfig({required this.valor, required this.etiqueta, this.icono});

  final String valor;
  final String etiqueta;
  final String? icono;

  factory OpcionConfig.fromJson(Map<String, dynamic> j) => OpcionConfig(
        valor: '${j['valor'] ?? ''}',
        etiqueta: '${j['etiqueta'] ?? j['valor'] ?? ''}',
        icono: j['icono'] == null ? null : '${j['icono']}',
      );
}

class CampoConfig {
  const CampoConfig({
    required this.clave,
    required this.etiqueta,
    required this.tipo,
    this.unidad,
    this.min = 0,
    this.max = 9999,
    this.paso = 1,
    this.valorPorDefecto,
    this.opciones = const [],
    this.obligatorio = false,
  });

  /// Clave snake_case con la unidad en el nombre (`kg_aplicados`, `peso_g`).
  final String clave;
  final String etiqueta;
  final CampoTipo tipo;
  final String? unidad;
  final num min;
  final num max;
  final num paso;
  final String? valorPorDefecto;
  final List<OpcionConfig> opciones;
  final bool obligatorio;

  bool get esRenderizable => tipo != CampoTipo.desconocido && clave.isNotEmpty;

  factory CampoConfig.fromJson(Map<String, dynamic> j) {
    final List<OpcionConfig> opciones = <OpcionConfig>[];
    final Object? crudo = j['opciones'];
    if (crudo is List) {
      for (final Object? o in crudo) {
        if (o is Map<String, dynamic>) opciones.add(OpcionConfig.fromJson(o));
      }
    }
    return CampoConfig(
      clave: '${j['clave'] ?? ''}',
      etiqueta: '${j['etiqueta'] ?? j['clave'] ?? ''}',
      tipo: CampoTipo.desdeNombre(j['tipo'] as String?),
      unidad: j['unidad'] == null ? null : '${j['unidad']}',
      min: _num(j['min'], 0),
      max: _num(j['max'], 9999),
      paso: _num(j['paso'], 1),
      valorPorDefecto: j['default'] == null ? null : '${j['default']}',
      opciones: opciones,
      obligatorio: j['obligatorio'] == true,
    );
  }

  /// Convierte la respuesta del widget (String/int/bool) al tipo escalar que
  /// va al JSON: sin esto el stepper escribiria "12" como string y el JSONB del
  /// server dejaria de ser consultable numericamente.
  Object? normalizar(Object? bruto) {
    if (bruto == null) return null;
    switch (tipo) {
      case CampoTipo.entero:
        if (bruto is int) return bruto;
        if (bruto is num) return bruto.round();
        return int.tryParse('$bruto') ?? double.tryParse('$bruto')?.round();
      case CampoTipo.decimal:
        if (bruto is num) return bruto.toDouble();
        return double.tryParse('$bruto');
      case CampoTipo.booleano:
        if (bruto is bool) return bruto;
        final String s = '$bruto'.toLowerCase();
        return s == 'true' || s == '1' || s == 'si';
      case CampoTipo.seleccion:
      case CampoTipo.texto:
        return '$bruto';
      case CampoTipo.desconocido:
        return null;
    }
  }

  static num _num(Object? v, num defecto) => v is num ? v : (num.tryParse('$v') ?? defecto);
}

class TareaConfig {
  const TareaConfig({
    required this.plantillaId,
    required this.nombre,
    required this.icono,
    required this.color,
    required this.orden,
    required this.etiquetaAccion,
    required this.version,
    required this.campos,
    this.dominio = 'tarea',
    this.configRota = false,
  });

  final String plantillaId;
  final String nombre;

  /// Nombre de icono (clave del catalogo visual en `iconos_campo.dart`), no un
  /// IconData: el modelo de dominio no puede importar Flutter.
  final String icono;

  /// ARGB sin signo, resuelto desde `#RRGGBB`.
  final int color;
  final int orden;
  final String etiquetaAccion;
  final int version;
  final List<CampoConfig> campos;

  /// `tarea` | `crianza`: los tipos de evento de poza comparten catalogo.
  final String dominio;

  /// True cuando el JSON no se pudo parsear. El boton SIGUE apareciendo: en
  /// campo es mejor registrar la actividad sin detalles que perderse la
  /// jornada por un typo del admin.
  final bool configRota;

  bool get requiereFormulario => campos.where((c) => c.esRenderizable).isNotEmpty;

  List<CampoConfig> get camposVisibles =>
      campos.where((c) => c.esRenderizable).toList(growable: false);

  /// Claves obligatorias sin respuesta. Es la unica validacion de campo que
  /// conviene hacer en el dispositivo: cuesta cero y evita subir basura.
  List<String> faltantes(Map<String, Object?> respuestas) {
    return camposVisibles
        .where((c) => c.obligatorio && (respuestas[c.clave] == null || '${respuestas[c.clave]}'.isEmpty))
        .map((c) => c.clave)
        .toList(growable: false);
  }

  /// Respuestas del formulario -> `metadata` plano y tipado listo para JSON.
  Map<String, Object?> metadataDesde(Map<String, Object?> respuestas) {
    final Map<String, Object?> out = <String, Object?>{};
    for (final CampoConfig c in camposVisibles) {
      final Object? v = c.normalizar(respuestas[c.clave]);
      if (v != null) out[c.clave] = v;
    }
    return out;
  }

  factory TareaConfig.fromJson({
    required String plantillaId,
    required String nombre,
    required Map<String, dynamic> j,
  }) {
    final Object? ui = j['ui'];
    final Map<String, dynamic> mapa = ui is Map<String, dynamic> ? ui : <String, dynamic>{};

    final List<CampoConfig> campos = <CampoConfig>[];
    final Object? crudo = j['campos'];
    if (crudo is List) {
      for (final Object? c in crudo) {
        if (c is Map<String, dynamic>) campos.add(CampoConfig.fromJson(c));
      }
    }

    final int? orden = mapa['orden'] is num ? (mapa['orden'] as num).toInt() : null;

    return TareaConfig(
      plantillaId: plantillaId,
      nombre: nombre,
      icono: '${mapa['icono'] ?? 'check_circle'}',
      color: _color('${mapa['color'] ?? ''}', 0xFF22C55E),
      orden: orden ?? 100,
      etiquetaAccion: '${mapa['etiqueta_accion'] ?? nombre}',
      version: j['version'] is num ? (j['version'] as num).toInt() : 1,
      campos: campos,
      dominio: '${j['dominio'] ?? 'tarea'}',
    );
  }

  /// Punto de entrada desde la fila de Drift (TEXT con JSON).
  factory TareaConfig.fromMetadataTexto({
    required String plantillaId,
    required String nombre,
    required String metadataJson,
  }) {
    try {
      final Object? decodificado = jsonDecode(metadataJson.isEmpty ? '{}' : metadataJson);
      if (decodificado is! Map<String, dynamic>) throw const FormatException('no es objeto');
      return TareaConfig.fromJson(plantillaId: plantillaId, nombre: nombre, j: decodificado);
    } catch (_) {
      // JSON mal formado, metadata legacy sin `ui`, o columnas anidadas.
      return TareaConfig(
        plantillaId: plantillaId,
        nombre: nombre,
        icono: 'help',
        color: 0xFFF59E0B,
        orden: 9999,
        etiquetaAccion: nombre,
        version: 0,
        campos: const [],
        configRota: true,
      );
    }
  }

  /// Fallback cuando el server todavia no devolvio catalogo: el productor puede
  /// seguir trabajando con las plantillas sembradas localmente.
  static TareaConfig simple({required String id, required String nombre}) => TareaConfig(
        plantillaId: id,
        nombre: nombre,
        icono: 'check_circle',
        color: 0xFF22C55E,
        orden: 100,
        etiquetaAccion: nombre,
        version: 1,
        campos: const [],
      );

  static int _color(String hex, int defecto) {
    String s = hex.replaceFirst('#', '').trim();
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return defecto;
    return int.tryParse(s, radix: 16) ?? defecto;
  }
}
