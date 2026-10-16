/// De qué está hecho el almacén seguro del equipo (Supuesto S10, ADR-006).
enum NivelAlmacenSeguro {
  /// Keystore en TEE o StrongBox (Android), o Keychain (iOS): se sigue sin preguntar.
  hardware,

  /// Keystore por software (Android): hace falta el consentimiento explícito de HU-AUTH-009.
  software,
}

/// Lo que la app necesita saber de la seguridad del equipo antes de crear la DB local
/// (HU-AUTH-009, ADR-006).
///
/// Puerto en Dart puro. La implementación de producción es `SeguridadDispositivoCanal`, que le
/// pregunta a un canal nativo chico (Kotlin en Android, Swift en iOS); la de tests es
/// `SeguridadDispositivoFija`. Lanza [SeguridadDispositivoException] si la plataforma no responde.
abstract interface class SeguridadDispositivo {
  /// Si el equipo tiene bloqueo de pantalla: PIN, patrón, contraseña o biometría
  /// (`KeyguardManager.isDeviceSecure` en Android, `deviceOwnerAuthentication` en iOS). Sin él no
  /// se inicializa la DB (ADR-006).
  Future<bool> tieneBloqueoPantalla();

  /// Nivel del almacén seguro. En Android crea una clave de prueba en el Keystore y lee su
  /// `KeyInfo` (`securityLevel` en API 31+, `isInsideSecureHardware` antes). En iOS siempre es
  /// [NivelAlmacenSeguro.hardware]: S10 no aplica.
  Future<NivelAlmacenSeguro> nivelAlmacenSeguro();
}

/// La plataforma no pudo responder por la seguridad del equipo. [causa] va a logs, nunca al
/// usuario.
final class SeguridadDispositivoException implements Exception {
  const SeguridadDispositivoException({required this.operacion, this.causa});

  /// `bloqueoPantalla` o `nivelAlmacen`.
  final String operacion;

  final Object? causa;

  @override
  String toString() => 'SeguridadDispositivoException($operacion)';
}
