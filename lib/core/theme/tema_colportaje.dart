import 'package:flutter/material.dart';

import 'colores_colportaje.dart';

/// El tema del diseño "Login Colportor": paleta única 1b "Crema sobria" (#121, decisión de
/// Cristian) — sin tema oscuro ni variante clara/oscura. La propuesta 1a "Navy inmersivo" (tema
/// oscuro con acento dorado) queda descartada.
///
/// Ninguna pantalla debería tener un `Color(0x...)` propio: todo sale de `Theme.of(context)`.

const _navy = Color(0xFF002856);
const _navyHover = Color(0xFF13407A);
const _tinta = Color(0xFF0E1A2B);
const _textoSecundario = Color(0xFF2A3A52);
const _crema = Color(0xFFFAFAF7);
const _superficie = Color(0xFFFFFFFF);

ThemeData temaClaro() {
  const colores = ColoresColportaje.unica;
  final colorScheme = ColorScheme.light(
    primary: _navy,
    onPrimary: Colors.white,
    secondary: _navyHover,
    onSecondary: Colors.white,
    surface: _crema,
    onSurface: _tinta,
    surfaceContainerHighest: _superficie,
    onSurfaceVariant: _textoSecundario,
    outline: colores.bordeInput,
  );

  final textTheme = _textTheme(colorScheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: _crema,
    fontFamily: 'Inter',
    textTheme: textTheme,
    dividerTheme: DividerThemeData(color: colores.borde, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      // No `colores.placeholder` acá: a 2,5:1 contra el fondo no llega al 4,5:1 que pide WCAG para
      // texto chico y el hint queda visible en cualquier campo vacío (#121).
      hintStyle: textTheme.bodyLarge?.copyWith(color: colores.gris),
      errorStyle: TextStyle(color: colorScheme.error, fontSize: 12),
      border: UnderlineInputBorder(borderSide: BorderSide(color: colores.bordeInput, width: 1.5)),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colores.bordeInput, width: 1.5),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.primary.withValues(alpha: .5),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 17),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurfaceVariant,
        side: BorderSide(color: colores.borde, width: 1.5),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStatePropertyAll(colorScheme.primary),
      checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
      side: BorderSide(color: colores.bordeInput, width: 1.5),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    extensions: const [colores],
  );
}

TextTheme _textTheme(Color colorTexto) {
  return TextTheme(
    // Kicker: "COLPORTAJE · URUGUAY".
    labelSmall: TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 10,
      letterSpacing: 2.0,
      fontWeight: FontWeight.w600,
      color: colorTexto,
    ),
    // Título: "Iniciá tu jornada". Serif 600 (#121): Source Serif 4.
    headlineMedium: TextStyle(
      fontFamily: 'SourceSerif4',
      fontSize: 30,
      fontWeight: FontWeight.w600,
      height: 1.15,
      color: colorTexto,
    ),
    // Label de campo en mayúsculas: "CORREO O CÉDULA".
    labelMedium: TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 10.5,
      letterSpacing: 1.3,
      fontWeight: FontWeight.w600,
      color: colorTexto,
    ),
    // Texto de input.
    bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 15, color: colorTexto),
    // Pie, línea grande: "¿No tenés cuenta? Registrate".
    bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: colorTexto),
    // Pie, línea chica / divisor: "O CONTINUAR CON".
    bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 11, color: colorTexto),
  );
}
