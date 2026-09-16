import '../models/sesion_model.dart';

/// Origen remoto de autenticación. La implementación real envuelve `supabase_flutter`
/// (Sprint 3, HU-AUTH-003); hasta entonces se usa [AuthRemoteDataSourceEnMemoria].
///
/// Los data sources **sí lanzan excepciones** ([AuthRemoteException]); es el repositorio quien las
/// traduce a `Failure`. Así el dominio nunca ve una excepción de infraestructura.
abstract interface class AuthRemoteDataSource {
  Future<SesionModel> iniciarSesion({required String email, required String password});

  /// Supabase Auth `signUp` — pendiente, hoy solo fake (HU-AUTH-001, ver issue #14). Deja la
  /// sesión iniciada; con Supabase real puede requerir verificación de email primero
  /// (HU-AUTH-002, no decidido).
  Future<SesionModel> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  });

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

final class ServidorException extends AuthRemoteException {
  const ServidorException({this.status});

  final int? status;

  @override
  String toString() => 'ServidorException(status: $status)';
}
