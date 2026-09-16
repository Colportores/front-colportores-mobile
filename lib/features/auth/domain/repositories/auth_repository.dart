import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/sesion.dart';

/// Contrato del repositorio de autenticación. Interfaz en `domain`; implementación en `data`
/// (`AuthRepositoryImpl`), que combina el data source remoto (Supabase Auth) y el local
/// (secure_storage).
abstract interface class AuthRepository {
  /// Inicia sesión y deja la sesión persistida en el dispositivo.
  Future<Either<Failure, Sesion>> iniciarSesion({required String email, required String password});

  /// Registra una cuenta nueva y deja la sesión iniciada (HU-AUTH-001, versión mockeada — ver
  /// dartdoc de `RegistrarUsuarioUseCase` sobre qué puede cambiar con Supabase Auth real).
  Future<Either<Failure, Sesion>> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  });

  /// Inicia sesión con Google (OAuth por navegador; registra la cuenta si es el primer ingreso)
  /// y deja la sesión persistida en el dispositivo.
  Future<Either<Failure, Sesion>> iniciarSesionConGoogle();

  /// Sesión guardada en el dispositivo, o `null` si nunca hubo login o se cerró.
  Future<Either<Failure, Sesion?>> sesionActual();

  /// Cierra la sesión remota (si hay red) y borra la local siempre.
  Future<Either<Failure, Unit>> cerrarSesion();
}
