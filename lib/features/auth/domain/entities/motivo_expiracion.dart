/// Por qué la app cerró la sesión sin que el usuario lo pidiera (HU-AUTH-007).
enum MotivoExpiracion {
  /// Pasaron 30 días sin actividad de red (`PoliticaSesion`).
  inactividad,

  /// El servidor ya no acepta la sesión: se revocó (cambio de contraseña, cierre de sesión en
  /// todos los equipos) o venció de su lado.
  revocada,
}
