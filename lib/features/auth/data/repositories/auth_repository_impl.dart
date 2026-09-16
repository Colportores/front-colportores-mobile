import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';

/// Implementación de [AuthRepository]. Plantilla de referencia para los repositorios del proyecto:
///
/// - Orquesta data sources (remoto + local) y decide el orden: primero remoto, luego persiste.
/// - Traduce **toda** excepción de infraestructura a un [Failure]; nunca deja escapar una.
/// - Devuelve entidades de dominio (`toEntity()`), no modelos.
/// - Loguea solo UUIDs y códigos (convenciones §7.5).
///
/// Auth es la única feature cuya escritura no pasa por `sync_queue`: la sesión no es un dato de
/// negocio que se sincronice (ADR-006), es la credencial con la que se sincroniza.
final class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, Sesion>> iniciarSesion({
    required String email,
    required String password,
  }) async {
    try {
      final sesion = await _remote.iniciarSesion(email: email, password: password);
      await _local.guardarSesion(sesion);
      _log.info(LogModulo.auth, 'LOGIN_OK', 'login exitoso', {'user_id': sesion.usuarioId});
      return Right(sesion.toEntity());
    } on AuthRemoteException catch (e) {
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'LOGIN_FAIL', 'login rechazado', {'codigo': failure.codigo});
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'LOGIN_FAIL', 'error inesperado en login', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Sesion>> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    try {
      final sesion = await _remote.registrar(
        nombre: nombre,
        apellido: apellido,
        cedula: cedula,
        email: email,
        password: password,
      );
      await _local.guardarSesion(sesion);
      _log.info(LogModulo.auth, 'REGISTRO_OK', 'registro exitoso', {'user_id': sesion.usuarioId});
      return Right(sesion.toEntity());
    } on AuthRemoteException catch (e) {
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'REGISTRO_FAIL', 'registro rechazado', {'codigo': failure.codigo});
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'REGISTRO_FAIL', 'error inesperado en registro', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Sesion?>> sesionActual() async {
    try {
      final sesion = await _local.leerSesion();
      return Right(sesion?.toEntity());
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'SESION_LEER_FAIL', 'no se pudo leer la sesión', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Unit>> cerrarSesion() async {
    final sesion = await _local.leerSesion();
    try {
      if (sesion != null) await _remote.cerrarSesion(sesion.accessToken);
    } on SinConexionException {
      // Sin red igual se cierra localmente; la revocación remota queda para HU-AUTH-010.
      _log.warn(LogModulo.auth, 'LOGOUT_OFFLINE', 'logout sin conexión, solo local');
    } on AuthRemoteException catch (e) {
      _log.warn(LogModulo.auth, 'LOGOUT_REMOTO_FAIL', 'logout remoto falló', {
        'codigo': _traducir(e).codigo,
      });
    }

    try {
      await _local.borrarSesion();
      _log.info(LogModulo.auth, 'LOGOUT_OK', 'sesión cerrada', {'user_id': sesion?.usuarioId});
      return const Right(unit);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'LOGOUT_FAIL', 'no se pudo borrar la sesión', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  static Failure _traducir(AuthRemoteException e) => switch (e) {
    CredencialesInvalidasException() => const FailureCredencialesInvalidas(),
    CuentaPendienteException() => const FailureCuentaPendiente(),
    EmailYaRegistradoException() => const FailureEmailYaRegistrado(),
    SinConexionException() => const FailureSinConexion(),
    ServidorException(:final status) => FailureServidor(status: status),
  };
}
