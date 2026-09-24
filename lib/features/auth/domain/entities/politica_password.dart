/// Política de contraseña de la cuenta (Supuesto S1): la misma en el registro (HU-AUTH-001) y en
/// la contraseña nueva de la recuperación (HU-AUTH-005).
abstract final class PoliticaPassword {
  static final RegExp _regla = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');

  /// Texto que se muestra si [password] no cumple la política.
  static const String requisitos = 'Usá al menos 8 caracteres, una mayúscula y un número.';

  /// El error de [password] para el formulario, o `null` si cumple. [vacia] es el texto para la
  /// contraseña sin completar (cada pantalla nombra su campo).
  static String? validar(String password, {String vacia = 'Ingresá tu contraseña'}) {
    if (password.isEmpty) return vacia;
    if (!_regla.hasMatch(password)) return requisitos;
    return null;
  }
}
