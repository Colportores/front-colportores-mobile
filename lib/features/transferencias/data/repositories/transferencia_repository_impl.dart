import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/transferencia.dart';
import '../../domain/repositories/transferencia_repository.dart';
import '../datasources/transferencia_local_data_source_drift.dart';

/// Implementación de [TransferenciaRepository] sobre [TransferenciaLocalDataSourceDrift].
///
/// - Traduce el rechazo de la persistencia a su `Failure` y cualquier otra excepción a la falla de
///   guardado de la acción; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni los materiales ni el motivo del
///   rechazo (convenciones §7.5).
final class TransferenciaRepositoryImpl implements TransferenciaRepository {
  TransferenciaRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final TransferenciaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, TransferenciaPedida>> pedir(Transferencia transferencia) async {
    try {
      return Right(await _local.pedir(transferencia));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'TRANSFERENCIA_ALTA_FAIL',
        'falló el guardado de una transferencia',
        {'transferencia_id': transferencia.id, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureTransferenciaNoGuardada(causa: tipo));
    }
  }

  @override
  Future<Either<Failure, Transferencia>> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  }) async {
    try {
      return Right(await _local.cancelar(id: id, colportorId: colportorId, ahora: ahora));
    } on TransferenciaNoCancelableException {
      _log.info(LogModulo.db, 'TRANSFERENCIA_CANCELAR_RECHAZADO', 'no se puede cancelar', {
        'transferencia_id': id,
      });
      return const Left(FailureTransferenciaNoCancelable());
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'TRANSFERENCIA_CANCELAR_FAIL',
        'falló la cancelación de una transferencia',
        {'transferencia_id': id, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureTransferenciaNoCancelada(causa: tipo));
    }
  }

  @override
  Stream<List<Transferencia>> observar(String colportorId) =>
      _local.observar(colportorId).handleError((Object error, StackTrace st) {
        _log.error(
          LogModulo.db,
          'TRANSFERENCIA_STREAM_FAIL',
          'falló la lectura de las transferencias',
          {'tipo': error.runtimeType.toString()},
          null,
          st,
        );
        throw const FailureTransferenciasNoDisponibles();
      });
}
