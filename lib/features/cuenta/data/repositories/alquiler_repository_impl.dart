import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/alquiler.dart';
import '../../domain/repositories/alquiler_repository.dart';
import '../datasources/alquiler_local_data_source_drift.dart';

/// [AlquilerRepository] sobre [AlquilerLocalDataSourceDrift].
///
/// Si la base no se puede leer, el `Stream` falla con [FailureAlquilerNoDisponible] y no emite «sin
/// alquiler». Al log va solo el tipo de la excepción (convenciones §7.5): ni montos ni ids.
final class AlquilerRepositoryImpl implements AlquilerRepository {
  AlquilerRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AlquilerLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Stream<AlquilerDelColportor> observar(String colportorId) =>
      _local.observar(colportorId).handleError((Object error, StackTrace st) {
        _log.warn(LogModulo.db, 'CUENTA_ALQUILER_STREAM_FAIL', 'no se pudo armar Mi alquiler', {
          'tipo': error.runtimeType.toString(),
        });
        throw const FailureAlquilerNoDisponible();
      });
}

/// Sin DB abierta no hay de dónde calcular: el `Stream` falla con [FailureAlquilerNoDisponible].
final class AlquilerSinBase implements AlquilerRepository {
  const AlquilerSinBase();

  @override
  Stream<AlquilerDelColportor> observar(String colportorId) =>
      Stream<AlquilerDelColportor>.error(const FailureAlquilerNoDisponible());
}
