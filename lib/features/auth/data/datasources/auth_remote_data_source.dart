import '../models/sesion_model.dart';

/// Origen remoto de autenticación. La implementación real es `AuthRemoteDataSourceSupabase`
/// (HU-AUTH-003, envuelve `supabase_flutter`); sin `SUPABASE_URL`/`SUPABASE_ANON_KEY` se usa
/// `AuthRemoteDataSourceEnMemoria` (tests, CI, demo sin backend).
///
/// Los data sources **sí lanzan excepciones** ([AuthRemoteException]); es el repositorio quien las
/// traduce a `Failure`. Así el dominio nunca ve una excepción de infraestructura.
abstract interface class AuthRemoteDataSource {
  Future<SesionModel> iniciarSesion({required String email, required String password});

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

  Future<void> cerrarSesion(String accessToken);
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

/// Error del proveedor sin traducción propia. [mensaje], si viene, reemplaza el texto genérico
/// de `FailureServidor` (nunca lleva PII: sale de códigos de error, no de datos del usuario).
final class ServidorException extends AuthRemoteException {
  const ServidorException({this.status, this.mensaje});

  final int? status;
  final String? mensaje;

  @override
  String toString() => 'ServidorException(status: $status)';
}
