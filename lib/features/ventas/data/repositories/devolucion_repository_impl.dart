import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/devolucion.dart';
import '../../domain/entities/venta_para_devolver.dart';
import '../../domain/repositories/devolucion_repository.dart';
import '../datasources/devolucion_local_data_source_drift.dart';

/// Implementación de [DevolucionRepository] sobre [DevolucionLocalDataSourceDrift].
///
/// - Traduce cualquier excepción a su `Failure`; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: nada de la persona ni del motivo
///   (§7.5).
final class DevolucionRepositoryImpl implements DevolucionRepository {
  DevolucionRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final DevolucionLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, VentaParaDevolver?>> ventaParaDevolver(String ventaId) async {
    try {
      return Right(await _local.ventaParaDevolver(ventaId));
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'DEVOLUCION_LECTURA_FAIL',
        'falló la lectura de la venta para devolverla',
        {'venta_id': ventaId, 'tipo': tipo},
        null,
        st,
      );
      return const Left(FailureDevolucionNoDisponible());
    }
  }

  @override
  Future<Either<Failure, DevolucionRegistrada>> registrar(PedidoDeDevolucion pedido) async {
    try {
      return Right(await _local.registrar(pedido));
    } on DevolucionRechazadaException catch (e) {
      final (falla, motivo) = switch (e) {
        DevolucionSinVentaException() => (const FailureDevolucionSinVenta(), 'venta'),
        DevolucionFueraDePlazoException() => (const FailureDevolucionFueraDePlazo(), 'plazo'),
        DevolucionInvalidaException(:final causa) => (
          FailureDevolucionInvalida(causa: causa),
          causa,
        ),
      };
      _log.info(LogModulo.db, 'DEVOLUCION_ALTA_RECHAZADA', 'devolución rechazada', {
        'venta_id': pedido.ventaId,
        'motivo': motivo,
      });
      return Left(falla);
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'DEVOLUCION_ALTA_FAIL',
        'falló la devolución',
        {'venta_id': pedido.ventaId, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureDevolucionNoGuardada(causa: tipo));
    }
  }
}
