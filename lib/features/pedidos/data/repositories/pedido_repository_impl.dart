import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/pedido.dart';
import '../../domain/repositories/pedido_repository.dart';
import '../datasources/pedido_local_data_source_drift.dart';

/// Implementación de [PedidoRepository] sobre [PedidoLocalDataSourceDrift].
///
/// - Traduce el rechazo de la persistencia a su `Failure` y cualquier otra excepción a la falla de guardado
///   de la acción; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni los productos ni el motivo del rechazo
///   (convenciones §7.5).
final class PedidoRepositoryImpl implements PedidoRepository {
  PedidoRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final PedidoLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, PedidoEnviado>> enviar(Pedido pedido) async {
    try {
      return Right(await _local.enviar(pedido));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus parámetros.
      // Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'PEDIDO_ALTA_FAIL',
        'falló el guardado de un pedido',
        {'pedido_id': pedido.id, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailurePedidoNoGuardado(causa: tipo));
    }
  }

  @override
  Future<Either<Failure, Pedido>> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  }) async {
    try {
      return Right(await _local.cancelar(id: id, colportorId: colportorId, ahora: ahora));
    } on PedidoNoCancelableException {
      _log.info(LogModulo.db, 'PEDIDO_CANCELAR_RECHAZADO', 'no se puede cancelar', {
        'pedido_id': id,
      });
      return const Left(FailurePedidoNoCancelable());
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'PEDIDO_CANCELAR_FAIL',
        'falló la cancelación de un pedido',
        {'pedido_id': id, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailurePedidoNoCancelado(causa: tipo));
    }
  }

  @override
  Stream<List<Pedido>> observar(String colportorId) =>
      _local.observar(colportorId).handleError((Object error, StackTrace st) {
        _log.error(
          LogModulo.db,
          'PEDIDO_STREAM_FAIL',
          'falló la lectura de los pedidos',
          {'tipo': error.runtimeType.toString()},
          null,
          st,
        );
        throw const FailurePedidosNoDisponibles();
      });
}
