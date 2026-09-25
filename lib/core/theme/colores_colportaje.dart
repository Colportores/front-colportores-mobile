import 'package:flutter/material.dart';

/// Tokens de color del diseño "Login Colportor" (paleta única 1b "Crema sobria", #121) que
/// [ColorScheme] no cubre.
///
/// El resto de la paleta (navy, navyHover, tinta, crema, superficie, texto secundario) sí tiene
/// lugar natural en [ColorScheme] (`primary`, `secondary`, `surface`, `onSurface`,
/// `surfaceContainerHighest`, `onSurfaceVariant`) y se define ahí, en `tema_colportaje.dart`.
@immutable
class ColoresColportaje extends ThemeExtension<ColoresColportaje> {
  const ColoresColportaje({
    required this.gris,
    required this.placeholder,
    required this.borde,
    required this.bordeInput,
    required this.googleAzul,
  });

  /// Texto atenuado / labels de campo.
  final Color gris;

  /// Placeholders de input; texto de divisores y rótulos suaves.
  final Color placeholder;

  /// Líneas y bordes suaves (incluye el color de los divisores).
  final Color borde;

  /// Borde/underline de los inputs en reposo.
  final Color bordeInput;

  /// Letra "G" del botón de Google.
  final Color googleAzul;

  static const _gris = Color(0xFF5B6B82);
  static const _placeholder = Color(0xFF90A0B7);
  static const _borde = Color(0xFFE3E7EE);
  static const _bordeInput = Color(0xFFCFD6E1);
  static const _googleAzul = Color(0xFF4285F4);

  static const unica = ColoresColportaje(
    gris: _gris,
    placeholder: _placeholder,
    borde: _borde,
    bordeInput: _bordeInput,
    googleAzul: _googleAzul,
  );

  @override
  ColoresColportaje copyWith({
    Color? gris,
    Color? placeholder,
    Color? borde,
    Color? bordeInput,
    Color? googleAzul,
  }) {
    return ColoresColportaje(
      gris: gris ?? this.gris,
      placeholder: placeholder ?? this.placeholder,
      borde: borde ?? this.borde,
      bordeInput: bordeInput ?? this.bordeInput,
      googleAzul: googleAzul ?? this.googleAzul,
    );
  }

  @override
  ColoresColportaje lerp(ThemeExtension<ColoresColportaje>? other, double t) {
    if (other is! ColoresColportaje) return this;
    return ColoresColportaje(
      gris: Color.lerp(gris, other.gris, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      borde: Color.lerp(borde, other.borde, t)!,
      bordeInput: Color.lerp(bordeInput, other.bordeInput, t)!,
      googleAzul: Color.lerp(googleAzul, other.googleAzul, t)!,
    );
  }
}
