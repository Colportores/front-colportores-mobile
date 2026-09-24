import '../models/sesion_model.dart';

/// Origen remoto de autenticación. La implementación real es `AuthRemoteDataSourceSupabase`
/// (HU-AUTH-003, envuelve `supabase_flutter`); sin `SUPABASE_URL`/`SUPABASE_ANON_KEY` se usa
/// `AuthRemoteDataSourceEnMemoria` (tests, CI, demo sin backend).
///
/// Los data sources **sí lanzan excepciones** ([AuthRemoteException]); es el repositorio quien las
/// traduce a `Failure`. Así el dominio nunca ve una excepción de infraestructura.
abstract interface class AuthRemoteDataSource {
  Future<SesionModel> iniciarSesion({required String email, required String password});

  /// Solicita el reset de contraseña (HU-AUTH-004, Supabase Auth `resetPasswordForEmail`).
  ///
  /// Nunca lanza para "el email no existe": Supabase responde igual exista o no la cuenta
  /// (anti-enumeración, OWASP) — solo puede lanzar por falta de red o por su propio rate limit
  /// de emails. El repositorio enmascara el rate limit como éxito, pero **no** la falta de red
  /// (ver `AuthRepositoryImpl.solicitarRecuperacionPassword` para el detalle de cada caso).
  Future<void> solicitarRecuperacionPassword(String email);

  /// Supabase Auth `signUp` (HU-AUTH-001/002). Devuelve la sesión si Supabase la deja iniciada,
  /// o `null` si la cuenta se creó pero falta confirmar el email ("Confirm email" activo) — eso
  /// **no** es un error, el fake en memoria no tiene ese paso intermedio y siempre devuelve
  /// sesión.
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  });

  /// Ingreso con Google vía OAuth por navegador + deep link (HU-AUTH-003). Con Supabase, el
  /// primer ingreso registra la cuenta en el mismo paso. Resuelve cuando la sesión ya está
  /// iniciada; si el usuario no vuelve de la pantalla de Google, lanza [ServidorException]
  /// con mensaje para el usuario.
  Future<SesionModel> iniciarSesionConGoogle();

  /// Sesión que el proveedor tiene persistida en el dispositivo (o `null`). Con Supabase la
  /// persiste `supabase_flutter` por su cuenta; si está vencida intenta refrescarla.
  Future<SesionModel?> obtenerSesionActual();

  /// Cierra la sesión del cliente: la revoca en el servidor y borra la copia que guarda el
  /// proveedor. Sin red, la copia local se borra igual y lanza [SinConexionException].
  Future<void> cerrarSesion(String accessToken);

  /// Revoca en el servidor **solo** la sesión de [accessToken] (scope local: ni las otras sesiones
  /// del usuario ni la que tenga el cliente ahora), sin tocar el cliente. Es para la revocación
  /// que un logout sin red dejó pendiente (HU-AUTH-006): para entonces el usuario pudo haber
  /// vuelto a entrar, y esa sesión nueva no se toca.
  Future<void> revocarSesion(String accessToken);

  /// Reenvía el email de verificación de una cuenta con confirmación pendiente (HU-AUTH-002,
  /// Supabase Auth `resend` tipo `signup`). El plan free de Supabase sin SMTP propio limita esto a
  /// ~2 emails por hora; ese límite llega como [ServidorException] (mismo código que cualquier
  /// otro rate limit de Supabase), no hace falta modelarlo aparte acá.
  Future<void> reenviarVerificacion(String email);

  /// Emite cada vez que el deep link de verificación de email (HU-AUTH-002) vuelve con un error:
  /// enlace vencido o ya usado. Supabase no distingue los dos casos (mismo `error_code`
  /// `otp_expired` para ambos), así que del lado de la app también es un solo evento.
  ///
  /// Cubre el caso donde el usuario abre el enlace sin tener la pantalla de verificación en
  /// pantalla (p. ej. la app estaba cerrada); la raíz de la app (`ColportoresApp`) lo escucha para
  /// llevarlo a esa pantalla en estado "expirado". El caso de éxito (enlace válido) no pasa por
  /// acá: se resuelve con el flujo normal de "Ya verifiqué mi email" de esa misma pantalla.
  Stream<void> get erroresVerificacionEmail;
}

/// Excepciones tipadas del origen remoto. Sin PII en [toString].
sealed class AuthRemoteException implements Exception {
  const AuthRemoteException();
}

final class CredencialesInvalidasException extends AuthRemoteException {
  const CredencialesInvalidasException();
}

final class CuentaPendienteException extends AuthRemoteException {
  const CuentaPendienteException();
}

/// Ya existe una cuenta con ese email (HU-AUTH-001).
final class EmailYaRegistradoException extends AuthRemoteException {
  const EmailYaRegistradoException();
}

final class SinConexionException extends AuthRemoteException {
  const SinConexionException();
}

/// La contraseña no cumple la política de Supabase Auth (`weak_password`).
final class PasswordDebilException extends AuthRemoteException {
  const PasswordDebilException();
}

/// La contraseña nueva es igual a la anterior (Supabase `same_password`, HU-AUTH-005).
final class PasswordIgualALaAnteriorException extends AuthRemoteException {
  const PasswordIgualALaAnteriorException();
}

/// La sesión que abrió el enlace de recuperación ya no sirve (venció, o no hay): hay que pedir un
/// enlace nuevo (HU-AUTH-005).
final class SesionDeRecuperacionVencidaException extends AuthRemoteException {
  const SesionDeRecuperacionVencidaException();
}

/// Error del proveedor sin traducción propia. [mensaje], si viene, reemplaza el texto genérico
/// de `FailureServidor` (nunca lleva PII: sale de códigos de error, no de datos del usuario).
final class ServidorException extends AuthRemoteException {
  const ServidorException({this.status, this.mensaje});

  final int? status;
  final String? mensaje;

  @override
  String toString() => 'ServidorException(status: $status)';
}
