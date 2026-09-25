import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/estado_cuenta.dart';
import '../../domain/repositories/cuenta_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/estado_cuenta_local_data_source.dart';
import '../datasources/estado_cuenta_remote_data_source.dart';

/// [CuentaRepository] sobre el BFF, recordando en el equipo el último estado que informó
/// (HU-AUTH-008), para que el colportor que abre la app sin señal no quede afuera.
final class CuentaRepositoryImpl implements CuentaRepository {
  CuentaRepositoryImpl(this._remote, this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final EstadoCuentaRemoteDataSource _remote;
  final EstadoCuentaLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, EstadoCuenta>> consultar(String usuarioId) async {
    final EstadoCuenta estado;
    try {
      estado = await _remote.consultar();
    } on SinConexionException {
      return const Left(FailureSinConexion());
    } on ServidorException catch (e) {
      _log.warn(LogModulo.auth, 'ESTADO_CUENTA_FAIL', 'el BFF respondió con error', {
        'status': e.status,
      });
      final mensaje = e.mensaje;
      return Left(
        mensaje == null
            ? FailureServidor(status: e.status)
            : FailureServidor(status: e.status, mensaje: mensaje),
      );
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'ESTADO_CUENTA_FAIL',
        'no se pudo consultar el estado de cuenta',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }

    try {
      await _local.guardar(usuarioId, estado);
    } on Object catch (e, st) {
      // El estado se consultó bien: que no se pueda recordar solo pesa en un arranque sin red.
      _log.error(
        LogModulo.auth,
        'ESTADO_CUENTA_GUARDAR_FAIL',
        'no se pudo recordar el estado de cuenta',
        const {},
        e,
        st,
      );
    }
    _log.info(LogModulo.auth, 'ESTADO_CUENTA', 'estado de cuenta consultado', {
      'user_id': usuarioId,
      'estado': estado.name,
    });
    return Right(estado);
  }

  @override
  Future<EstadoCuenta?> ultimoConocido(String usuarioId) async {
    try {
      return await _local.leer(usuarioId);
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'ESTADO_CUENTA_LEER_FAIL', 'no se pudo leer el último estado', {
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  }
}
