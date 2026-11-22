import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/resumen_de_cuenta.dart';
import '../../domain/repositories/resumen_de_cuenta_repository.dart';
import '../datasources/resumen_de_cuenta_local_data_source_drift.dart';

/// [ResumenDeCuentaRepository] sobre [ResumenDeCuentaLocalDataSourceDrift].
///
/// Si la base no se puede leer, el `Stream` falla con [FailureCuentaNoDisponible] y no emite ceros
/// que se lean como «no tenés nada». Al log va solo el tipo de la excepción (convenciones §7.5):
/// ni montos ni ids.
final class ResumenDeCuentaRepositoryImpl implements ResumenDeCuentaRepository {
  ResumenDeCuentaRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final ResumenDeCuentaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Stream<ResumenDeCuenta> observar(String colportorId) =>
      _local.observar(colportorId).handleError((Object error, StackTrace st) {
        _log.warn(LogModulo.db, 'CUENTA_RESUMEN_STREAM_FAIL', 'no se pudo calcular Mi Cuenta', {
          'tipo': error.runtimeType.toString(),
        });
        throw const FailureCuentaNoDisponible();
      });
}

/// Sin DB abierta no hay de dónde calcular: el `Stream` falla con [FailureCuentaNoDisponible].
final class ResumenDeCuentaSinBase implements ResumenDeCuentaRepository {
  const ResumenDeCuentaSinBase();

  @override
  Stream<ResumenDeCuenta> observar(String colportorId) =>
      Stream<ResumenDeCuenta>.error(const FailureCuentaNoDisponible());
}
