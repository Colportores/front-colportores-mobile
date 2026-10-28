import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/repositories/entrega_repository.dart';
import '../datasources/entrega_local_data_source_drift.dart';

/// Implementación de [EntregaRepository] sobre [EntregaLocalDataSourceDrift].
///
/// - Traduce cualquier excepción a su `Failure`; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: nada de la persona (§7.5).
final class EntregaRepositoryImpl implements EntregaRepository {
  EntregaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final EntregaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, EntregaRegistrada>> entregarAhora(
    String ventaId,
    List<Entrega> filas,
  ) async {
    try {
      return Right(await _local.entregarAhora(ventaId, filas));
    } on EntregaSinVentaException {
      _log.info(LogModulo.db, 'ENTREGA_ALTA_RECHAZADA', 'venta ausente', {
        'venta_id': ventaId,
        'motivo': 'venta',
      });
      return const Left(FailureEntregaNoGuardada(causa: 'EntregaSinVentaException'));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'ENTREGA_ALTA_FAIL',
        'falló la entrega',
        {'venta_id': ventaId, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureEntregaNoGuardada(causa: tipo));
    }
  }

  @override
  Future<Either<Failure, List<Entrega>>> deLaVenta(String ventaId) async {
    try {
      return Right(await _local.deLaVenta(ventaId));
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'ENTREGA_LECTURA_FAIL',
        'falló la lectura de las entregas',
        {'venta_id': ventaId, 'tipo': tipo},
        null,
        st,
      );
      return const Left(FailureEntregaNoDisponible());
    }
  }
}
