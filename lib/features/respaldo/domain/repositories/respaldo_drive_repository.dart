import 'package:dartz/dartz.dart' show Either, Unit;

import '../../../../core/error/failure.dart';
import '../entities/estado_respaldo_drive.dart';

/// El respaldo en el Google Drive de la persona: autorizar, ver cómo está y desconectar
/// (HU-SYNC-004). Todo es por usuario de la app ([usuarioId]).
///
/// El dominio no lanza: cada operación devuelve un `Either<Failure, …>`.
abstract interface class RespaldoDriveRepository {
  /// Cómo está el respaldo de [usuarioId]. `Left(FailureAlmacenSeguro)` si el almacén no se deja
  /// leer: no se afirma «sin conectar» sobre algo que no se pudo mirar.
  Future<Either<Failure, EstadoRespaldoDrive>> estado(String usuarioId);

  /// Abre la pantalla de Google, pide el permiso de Drive (solo `drive.appdata`) y deja guardada
  /// la cuenta. Después intenta el primer respaldo; que falle no desconecta.
  ///
  /// - `Left(FailureDriveCancelado)`: la persona cerró o rechazó la pantalla de Google.
  /// - `Left(FailureSinConexion)`: sin red.
  /// - `Left(FailureDrivePermisoIncompleto)`: Google conectó la cuenta pero sin el permiso de
  ///   Drive.
  /// - `Left(FailureDriveNoConectado)`: cualquier otra causa.
  Future<Either<Failure, ConexionDrive>> conectar(String usuarioId);

  /// Deja de usar la cuenta: olvida la cuenta guardada (los respaldos dejan de ejecutarse) y le
  /// pide a Google que retire el permiso. Los archivos ya subidos siguen en el Drive. Retirar el
  /// permiso en Google es de mejor esfuerzo: sin red no impide desconectar. Solo falla
  /// (`Left(FailureAlmacenSeguro)`) si la cuenta guardada no se pudo olvidar.
  Future<Either<Failure, Unit>> desconectar(String usuarioId);

  /// Mira si Google todavía tiene el permiso de [usuarioId]. Sin permiso lo deja en
  /// [DrivePermisoRevocado]. Sin red, o si Google no contesta, no concluye nada: devuelve el estado
  /// como estaba.
  Future<Either<Failure, EstadoRespaldoDrive>> verificarPermiso(String usuarioId);

  /// El respaldo recibió `401` de Drive (HU-SYNC-004, «Edge — usuario revoca el permiso»): pasa a
  /// [DrivePermisoRevocado]. Sin cuenta conectada no hace nada. Lo llama el motor de backup.
  Future<Either<Failure, EstadoRespaldoDrive>> marcarPermisoRevocado(String usuarioId);

  /// Drive contestó que no hay espacio (16D·10): pasa a [DriveSinEspacio]. Sin cuenta conectada no
  /// hace nada. Lo llama el motor de backup.
  Future<Either<Failure, EstadoRespaldoDrive>> marcarSinEspacio(String usuarioId);

  /// Un respaldo se guardó: si estaba en [DriveSinEspacio] vuelve a [DriveConectada]. Lo llama el
  /// motor de backup.
  Future<Either<Failure, EstadoRespaldoDrive>> marcarRespaldoGuardado(String usuarioId);

  /// El token de acceso de Drive de [usuarioId], pedido en silencio a Google (dura una hora; no se
  /// guarda). `null` si no hay cuenta conectada con permiso o no se pudo pedir. Sin permiso
  /// (Google ya no lo da) la cuenta pasa a [DrivePermisoRevocado]. Es lo que recibe
  /// `DriveArchive.token`.
  Future<String?> tokenDeAcceso(String usuarioId);
}

/// Quien hace el primer respaldo justo después de conectar (HU-SYNC-005, #185). Mientras el motor
/// de backup no esté armado en la app, [PrimerRespaldoSinMotor]: no hay primer respaldo y la
/// conexión lo dice con la verdad.
abstract interface class PrimerRespaldoDrive {
  /// `true` si el respaldo quedó subido; `false` o una excepción, si no. Nunca desconecta.
  Future<bool> hacer();
}

/// Sin motor de backup (hasta #185): no se hace ningún respaldo en el momento.
final class PrimerRespaldoSinMotor implements PrimerRespaldoDrive {
  const PrimerRespaldoSinMotor();

  @override
  Future<bool> hacer() async => false;
}
