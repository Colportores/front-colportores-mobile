/// Qué pasó con un enlace de recuperación de contraseña que llegó a la app (HU-AUTH-005).
enum EnlaceRecuperacion {
  /// El enlace sirvió: hay una sesión de recuperación y se puede fijar la contraseña nueva.
  valido,

  /// El enlace venció, ya se usó o no se pudo canjear en este teléfono (HU-AUTH-005, "Error -
  /// token expirado"): hay que pedir uno nuevo.
  vencido,
}
