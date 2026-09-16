import 'package:flutter/material.dart';

/// Tokens de color del diseño "Login Colportor" que [ColorScheme] no cubre.
///
/// El resto de la paleta (navy, navyHover, tinta, crema, superficie, texto secundario) sí tiene
/// lugar natural en [ColorScheme] (`primary`, `secondary`, `surface`, `onSurface`,
/// `surfaceContainerHighest`, `onSurfaceVariant`) y se define ahí, en `tema_colportaje.dart`.
@immutable
class ColoresColportaje extends ThemeExtension<ColoresColportaje> {
  const ColoresColportaje({
    required this.oro,
    required this.oroHover,
    required this.gris,
    required this.placeholder,
    required this.borde,
    required this.bordeInput,
    required this.googleAzul,
    required this.negro,
    required this.inputRelleno,
  });

  /// Acento dorado: logo, kicker, links y botón "Entrar" en el tema oscuro.
  final Color oro;

  /// Pressed/hover del botón dorado.
  final Color oroHover;

  /// Texto atenuado / labels de campo (claro: hex propio; oscuro: blanco al 70%, según diseño).
  final Color gris;

  /// Placeholders de input y texto de divisores.
  final Color placeholder;

  /// Líneas y bordes suaves (incluye el color de los divisores).
  final Color borde;

  /// Borde/underline de los inputs en reposo.
  final Color bordeInput;

  /// Letra "G" del botón de Google.
  final Color googleAzul;

  /// Fondo del botón de Apple en el tema oscuro.
  final Color negro;

  /// Relleno de los inputs (transparente en claro — son de línea; translúcido en oscuro).
  final Color inputRelleno;

  static const _oro = Color(0xFFC8A24A);
  static const _oroHover = Color(0xFFD8B25C);
  static const _griClaro = Color(0xFF5B6B82);
  static const _placeholder = Color(0xFF90A0B7);
  static const _bordeClaro = Color(0xFFE3E7EE);
  static const _bordeInputClaro = Color(0xFFCFD6E1);
  static const _googleAzul = Color(0xFF4285F4);
  static const _negro = Color(0xFF000000);

  /// rgba(255,255,255,.2) — divisores y bordes suaves del tema oscuro.
  static const _bordeOscuro = Color(0x33FFFFFF);

  /// rgba(255,255,255,.22) — borde de inputs en reposo, tema oscuro.
  static const _bordeInputOscuro = Color(0x38FFFFFF);

  /// rgba(255,255,255,.08) — relleno de inputs, tema oscuro.
  static const _inputRellenoOscuro = Color(0x14FFFFFF);

  static const claro = ColoresColportaje(
    oro: _oro,
    oroHover: _oroHover,
    gris: _griClaro,
    placeholder: _placeholder,
    borde: _bordeClaro,
    bordeInput: _bordeInputClaro,
    googleAzul: _googleAzul,
    negro: _negro,
    inputRelleno: Colors.transparent,
  );

  static const oscuro = ColoresColportaje(
    oro: _oro,
    oroHover: _oroHover,
    gris: Colors.white70, // "labels con opacidad .7" (diseño 1a)
    placeholder: _placeholder,
    borde: _bordeOscuro,
    bordeInput: _bordeInputOscuro,
    googleAzul: _googleAzul,
    negro: _negro,
    inputRelleno: _inputRellenoOscuro,
  );

  @override
  ColoresColportaje copyWith({
    Color? oro,
    Color? oroHover,
    Color? gris,
    Color? placeholder,
    Color? borde,
    Color? bordeInput,
    Color? googleAzul,
    Color? negro,
    Color? inputRelleno,
  }) {
    return ColoresColportaje(
      oro: oro ?? this.oro,
      oroHover: oroHover ?? this.oroHover,
      gris: gris ?? this.gris,
      placeholder: placeholder ?? this.placeholder,
      borde: borde ?? this.borde,
      bordeInput: bordeInput ?? this.bordeInput,
      googleAzul: googleAzul ?? this.googleAzul,
      negro: negro ?? this.negro,
      inputRelleno: inputRelleno ?? this.inputRelleno,
    );
  }

  @override
  ColoresColportaje lerp(ThemeExtension<ColoresColportaje>? other, double t) {
    if (other is! ColoresColportaje) return this;
    return ColoresColportaje(
      oro: Color.lerp(oro, other.oro, t)!,
      oroHover: Color.lerp(oroHover, other.oroHover, t)!,
      gris: Color.lerp(gris, other.gris, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      borde: Color.lerp(borde, other.borde, t)!,
      bordeInput: Color.lerp(bordeInput, other.bordeInput, t)!,
      googleAzul: Color.lerp(googleAzul, other.googleAzul, t)!,
      negro: Color.lerp(negro, other.negro, t)!,
      inputRelleno: Color.lerp(inputRelleno, other.inputRelleno, t)!,
    );
  }
}
