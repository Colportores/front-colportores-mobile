/// Qué pasó con un enlace de recuperación de contraseña que llegó a la app (HU-AUTH-005).
enum EnlaceRecuperacion {
  /// El enlace sirvió: hay una sesión de recuperación y se puede fijar la contraseña nueva.
  valido,

  /// El enlace venció, ya se usó o no se pudo canjear en este teléfono (HU-AUTH-005, "Error -
  /// token expirado"): hay que pedir uno nuevo.
  vencido,

  /// No se pudo canjear porque no había red o el servidor no respondió. El enlace **sigue
  /// sirviendo** (gotrue recién descarta el código cuando el servidor contesta): con conexión, se
  /// vuelve a abrir desde el correo. No deja sesión de recuperación.
  sinConexion,
}
