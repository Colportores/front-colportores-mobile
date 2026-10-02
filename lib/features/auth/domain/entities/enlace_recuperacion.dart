/// Qué pasó con un enlace de recuperación de contraseña que llegó a la app (HU-AUTH-005).
enum EnlaceRecuperacion {
  /// El enlace sirvió: hay una sesión de recuperación y se puede fijar la contraseña nueva.
  valido,

  /// El enlace venció o no se pudo canjear (HU-AUTH-005, "Error - token expirado"): hay que pedir
  /// uno nuevo.
  vencido,

  /// El enlace ya se usó (HU-AUTH-005, "Error - token reutilizado", 15-A07): Supabase lo rechaza
  /// con el mismo error que a uno vencido, y la app lo deduce porque este teléfono acaba de
  /// completar un cambio de contraseña con un enlace (`CambiosPorRecuperacion`). No ofrece pedir
  /// otro: ofrece volver al login.
  usado,

  /// No se pudo canjear porque no había red o el servidor no respondió. El enlace **sigue
  /// sirviendo** (gotrue recién descarta el código cuando el servidor contesta): con conexión, se
  /// vuelve a abrir desde el correo. No deja sesión de recuperación.
  sinConexion,
}
