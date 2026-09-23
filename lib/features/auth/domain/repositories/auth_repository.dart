import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/resultado_cierre_sesion.dart';
import '../entities/resultado_registro.dart';
import '../entities/sesion.dart';

/// Contrato del repositorio de autenticación. Interfaz en `domain`; implementación en `data`
/// (`AuthRepositoryImpl`), que combina el data source remoto (Supabase Auth) y el local
/// (secure_storage).
abstract interface class AuthRepository {
  /// Inicia sesión y deja la sesión persistida en el dispositivo.
  Future<Either<Failure, Sesion>> iniciarSesion({required String email, required String password});

  /// Solicita el reset de contraseña (HU-AUTH-004). Devuelve `Right(unit)` tanto si el email
  /// existe como si no (Supabase ni reporta esa diferencia) y también ante un rate limit del
  /// proveedor (anti-enumeración, OWASP + regla explícita de la HU de no revelar el límite) —
  /// pero un error genuino del servicio (caído, contrato roto) sí llega como `Left` visible: la
  /// HU hermana HU-AUTH-002 fija ese patrón y anti-enumeración no exige mentir cuando falla.
  Future<Either<Failure, Unit>> solicitarRecuperacionPassword({required String email});

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

  /// Cierra la sesión: revoca el JWT en Supabase y borra la sesión local (HU-AUTH-006).
  ///
  /// Sin red la sesión local se borra igual y la revocación queda pendiente
  /// ([ResultadoCierreSesion.revocacionPendiente]); se reintenta con
  /// [reintentarRevocacionPendiente]. `Left` solo si la sesión local no se pudo borrar: en ese caso
  /// el usuario **sigue** adentro (la sesión seguiría guardada) y puede reintentar.
  Future<Either<Failure, ResultadoCierreSesion>> cerrarSesion();

  /// Reintenta la revocación que un [cerrarSesion] sin red dejó pendiente. No-op si no hay.
  /// `Left(FailureSinConexion)` si sigue sin red (y sigue pendiente).
  Future<Either<Failure, Unit>> reintentarRevocacionPendiente();

  /// Reenvía el email de verificación de una cuenta con confirmación pendiente (HU-AUTH-002).
  Future<Either<Failure, Unit>> reenviarVerificacion({required String email});

  /// Emite cuando el deep link de verificación de email vuelve con un error (enlace vencido o ya
  /// usado — ver `AuthRemoteDataSource.erroresVerificacionEmail` en `data` para el detalle).
  Stream<void> get erroresVerificacionEmail;
}
