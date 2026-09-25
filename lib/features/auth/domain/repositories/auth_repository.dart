import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/motivo_expiracion.dart';
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

  /// Sesión guardada en el dispositivo, o `null` si nunca hubo login o se cerró. No toca la red:
  /// sin conexión, una sesión dentro de su ventana de 30 días sigue sirviendo (HU-AUTH-007).
  ///
  /// `Left(FailureSesionExpiradaPorInactividad)` si la sesión guardada venció por inactividad y ya
  /// se descartó al arrancar.
  Future<Either<Failure, Sesion?>> sesionActual();

  /// Renueva el JWT contra el servidor (HU-AUTH-007; ADR-007: el sync lo llama ante un `401` y
  /// reintenta). Hay un solo mecanismo de refresh: el del proveedor, que también renueva solo
  /// mientras la app está abierta. Varias llamadas a la vez comparten un único refresh.
  ///
  /// `Left(FailureSinConexion)`: se mantiene la sesión anterior y se reintenta más tarde.
  /// `Left(FailureSesionRevocada)`: el servidor ya no la acepta; además emite en [expiraciones].
  Future<Either<Failure, Sesion>> renovarSesion();

  /// Emite cuando la sesión termina sin que el usuario lo pida: el servidor rechazó el refresh
  /// ([MotivoExpiracion.revocada]) o, con la app abierta, pasaron 30 días sin actividad de red
  /// ([MotivoExpiracion.inactividad]).
  Stream<MotivoExpiracion> get expiraciones;

  /// Descarta la sesión guardada porque venció ([motivo]). A diferencia de [cerrarSesion] no
  /// espera a la red: el servidor ya no la acepta o la ventana de 30 días se cumplió. Los datos
  /// locales no se tocan.
  Future<Either<Failure, Unit>> expirarSesion(MotivoExpiracion motivo);

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

  /// Confirma la contraseña de la cuenta de [sesion] con un login nuevo del mismo email
  /// (HU-AUTH-009: una sesión restaurada no la tiene, y la DB local la necesita). Mismo resultado
  /// que [iniciarSesion]; la sesión nueva queda persistida.
  ///
  /// El login crea otra sesión en el servidor sin cerrar la que reemplaza (revisión del PR #130,
  /// N3): si sale bien, esa se revoca **sola** (scope local), best-effort y sin esperarla. Se
  /// revoca con el token que el proveedor tiene **antes** del login —lo renueva solo, así que es
  /// el vigente—, no con el de [sesion], que es el del arranque y pudo vencer. Nunca la nueva. Si
  /// la revocación falla, queda un warn y la sesión vieja vive hasta que venza sola.
  Future<Either<Failure, Sesion>> confirmarPassword({
    required Sesion sesion,
    required String password,
  });

  /// Reenvía el email de verificación de una cuenta con confirmación pendiente (HU-AUTH-002).
  Future<Either<Failure, Unit>> reenviarVerificacion({required String email});

  /// Emite cuando el deep link de verificación de email vuelve con un error (enlace vencido o ya
  /// usado — ver `AuthRemoteDataSource.erroresVerificacionEmail` en `data` para el detalle).
  Stream<void> get erroresVerificacionEmail;

  /// Emite cuando el deep link de verificación de email vuelve válido (issue #84 — ver
  /// `AuthRemoteDataSource.verificacionesExitosas` en `data` para el detalle).
  Stream<void> get verificacionesExitosas;
}
