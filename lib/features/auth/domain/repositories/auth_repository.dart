import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/resultado_registro.dart';
import '../entities/sesion.dart';

/// Contrato del repositorio de autenticación. Interfaz en `domain`; implementación en `data`
/// (`AuthRepositoryImpl`), que combina el data source remoto (Supabase Auth) y el local
/// (secure_storage).
abstract interface class AuthRepository {
  /// Inicia sesión y deja la sesión persistida en el dispositivo.
  Future<Either<Failure, Sesion>> iniciarSesion({required String email, required String password});

  /// Registra una cuenta nueva. Deja la sesión iniciada si Supabase la devuelve, o `null` en
  /// [ResultadoRegistro.sesion] si falta confirmar el email (HU-AUTH-001/002).
  Future<Either<Failure, ResultadoRegistro>> registrar({
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
