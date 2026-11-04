import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/detalle_de_mi_plata.dart';
import '../../domain/repositories/detalle_de_mi_plata_repository.dart';
import '../datasources/detalle_de_mi_plata_local_data_source_drift.dart';

/// [DetalleDeMiPlataRepository] sobre [DetalleDeMiPlataLocalDataSourceDrift].
///
/// Si la base no se puede leer, el `Stream` falla con [FailureCuentaNoDisponible] y no emite ceros
/// que se lean como «no tenés nada». Al log va solo el tipo de la excepción (convenciones §7.5):
/// ni montos, ni nombres, ni ids.
final class DetalleDeMiPlataRepositoryImpl implements DetalleDeMiPlataRepository {
  DetalleDeMiPlataRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final DetalleDeMiPlataLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Stream<DetalleDeMiPlata> observar(String colportorId) =>
      _local.observar(colportorId).handleError((Object error, StackTrace st) {
        _log.warn(LogModulo.db, 'CUENTA_DETALLE_STREAM_FAIL', 'no se pudo calcular Mi plata', {
          'tipo': error.runtimeType.toString(),
        });
        throw const FailureCuentaNoDisponible();
      });
}

/// Sin DB abierta no hay de dónde calcular: el `Stream` falla con [FailureCuentaNoDisponible].
final class DetalleDeMiPlataSinBase implements DetalleDeMiPlataRepository {
  const DetalleDeMiPlataSinBase();

  @override
  Stream<DetalleDeMiPlata> observar(String colportorId) =>
      Stream<DetalleDeMiPlata>.error(const FailureCuentaNoDisponible());
}
