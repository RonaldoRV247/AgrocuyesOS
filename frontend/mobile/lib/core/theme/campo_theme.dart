import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Dimensiones tactiles: requisito duro, no decoracion.
///
/// 60dp es el PISO exigido; el default real es 72dp porque en campo se toca con
/// guantes, con una mano y sobre pantallas con reflejos. Ningun widget de esta
/// app debe bajar de [kTouchMin]: esta aqui como constante para que el reviewer
/// lo pueda medir en un solo lugar.
/// ---------------------------------------------------------------------------
const double kTouchMin = 60.0;
const double kTouchDefault = 72.0;
const double kStepperButton = 76.0;

/// Boton de tarea: se espera con el pulgar sin mirar la pantalla.
const double kTaskButtonHeight = 112.0;

/// Ancho minimo de tile en la cuadrilla de tareas. Con 2 columnas en un telefono
/// de 360dp quedan tiles de ~170dp: dos pulgares no se solapan.
const double kGridTileMin = 164.0;
const double kGridGap = 12.0;

/// ---------------------------------------------------------------------------
/// Paleta de exterior. Criterio: contraste AA+ medido sobre cada par, porque a
/// 1000 nits de sol una sombra "bonita" desaparece.
/// Verde azulado #22C55E sobre negro de campo (#06130A) da ~8.4:1; el texto
/// secundario mas claro que se usa es #B8C2AE sobre #1B2416 (~7.6:1).
/// ---------------------------------------------------------------------------
class CampoColores {
  static const Color fondo = Color(0xFF0F1410);
  static const Color superficie = Color(0xFF1B2416);
  static const Color borde = Color(0xFF3A4A33);

  static const Color accion = Color(0xFF22C55E);
  static const Color sobreAccion = Color(0xFF06130A);

  /// Mortandad, rechazo del server, errores.
  static const Color alerta = Color(0xFFEF4444);
  static const Color sobreAlerta = Color(0xFFFFFFFF);

  /// Datos que aun no subieron: nunca rojo (no es un error del productor).
  static const Color pendienteDeSync = Color(0xFFF59E0B);

  static const Color texto = Color(0xFFF7F7F2);
  static const Color textoSecundario = Color(0xFFB8C2AE);
}

ThemeData construirTemaCampo() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: CampoColores.accion,
      brightness: Brightness.dark,
    ).copyWith(
      primary: CampoColores.accion,
      onPrimary: CampoColores.sobreAccion,
      surface: CampoColores.superficie,
      onSurface: CampoColores.texto,
      error: CampoColores.alerta,
      onError: CampoColores.sobreAlerta,
    ),
    scaffoldBackgroundColor: CampoColores.fondo,
  );

  return base.copyWith(
    textTheme: base.textTheme
        // Textos grandes: el productor no acerca la cara a la pantalla bajo el
        // sol. 22/34/44 son titulos de boton, de valor y de contador.
        .apply(
          bodyColor: CampoColores.texto,
          displayColor: CampoColores.texto,
        )
        .copyWith(
          titleLarge: base.textTheme.titleLarge
              ?.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
          headlineMedium: base.textTheme.headlineMedium
              ?.copyWith(fontSize: 34, fontWeight: FontWeight.w900),
          displaySmall: base.textTheme.displaySmall
              ?.copyWith(fontSize: 44, fontWeight: FontWeight.w900),
        ),
    // Que nada se vuelva habilitable con area menor a 60dp.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, kTouchDefault),
        backgroundColor: CampoColores.accion,
        foregroundColor: CampoColores.sobreAccion,
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: CampoColores.superficie,
      contentTextStyle: TextStyle(color: CampoColores.texto, fontSize: 18),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
