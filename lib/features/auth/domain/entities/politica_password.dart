import 'package:characters/characters.dart';

/// Política de contraseña de la cuenta (Supuesto S1): la misma en el registro (HU-AUTH-001) y en
/// la contraseña nueva de la recuperación (HU-AUTH-005).
///
/// Decisión de Cristian (02/10): la mayúscula es **cualquier letra mayúscula** (también con tilde y
/// la Ñ: «Ñandú2026» y «Élan2026» cumplen) y el largo se cuenta por **caracteres visibles** (un
/// emoji es 1, no los 2 o más que ocupa en la cadena).
abstract final class PoliticaPassword {
  static const int largoMinimo = 8;

  static final RegExp _mayuscula = RegExp(r'\p{Lu}', unicode: true);
  static final RegExp _numero = RegExp(r'\d');

  /// Texto que se muestra si [password] no cumple la política.
  static const String requisitos = 'Usá al menos 8 caracteres, una mayúscula y un número.';

  /// Cuántos caracteres visibles tiene [password] (un emoji, aunque lleve varios códigos, es 1).
  static int largo(String password) => password.characters.length;

  static bool cumpleLargo(String password) => largo(password) >= largoMinimo;

  /// Si tiene alguna letra mayúscula, de cualquier alfabeto (Ñ, É, Ü…).
  static bool tieneMayuscula(String password) => _mayuscula.hasMatch(password);

  static bool tieneNumero(String password) => _numero.hasMatch(password);

  /// El error de [password] para el formulario, o `null` si cumple. [vacia] es el texto para la
  /// contraseña sin completar (cada pantalla nombra su campo).
  static String? validar(String password, {String vacia = 'Ingresá tu contraseña'}) {
    if (password.isEmpty) return vacia;
    if (!cumpleLargo(password) || !tieneMayuscula(password) || !tieneNumero(password)) {
      return requisitos;
    }
    return null;
  }
}
