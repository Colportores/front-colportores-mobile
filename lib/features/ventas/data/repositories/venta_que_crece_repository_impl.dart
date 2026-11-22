import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/entities/venta_abierta.dart';
import '../../domain/entities/venta_item.dart';
import '../../domain/repositories/venta_que_crece_repository.dart';
import '../datasources/venta_local_data_source_drift.dart';

/// Implementación de [VentaQueCreceRepository] sobre [VentaLocalDataSourceDrift].
///
/// Traduce la venta que ya no está abierta a [FailureVentaCerrada] y cualquier otra excepción a
/// [FailureVentaNoGuardada]; nunca deja escapar una. Loguea solo UUIDs y códigos (convenciones §7.5).
final class VentaQueCreceRepositoryImpl implements VentaQueCreceRepository {
  VentaQueCreceRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final VentaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Stream<List<VentaAbierta>> observarAbiertasDe(String personaId) =>
      _local.observarAbiertasDe(personaId);

  @override
  Future<Either<Failure, CitasDeLaVenta>> citasDe(String ventaId) async {
    try {
      return Right(await _local.citasDe(ventaId));
    } on Object catch (e) {
      _log.warn(LogModulo.db, 'VENTA_CITAS_FAIL', 'no se pudieron leer las citas de la venta', {
        'venta_id': ventaId,
        'tipo': e.runtimeType.toString(),
      });
      return const Left(FailureVentaNoGuardada());
    }
  }

  @override
  Future<Either<Failure, VentaQueCrecio>> sumar(
    String ventaId,
    List<VentaItem> itemsNuevos, {
    required String numeroTalonario,
    required int sumadoCentavos,
    required DateTime ahora,
    String? motivoMontoManual,
    int? diferenciaCentavos,
  }) async {
    try {
      return Right(
        await _local.sumar(
          ventaId,
          itemsNuevos,
          sumadoCentavos: sumadoCentavos,
          ahora: ahora,
          motivoMontoManual: motivoMontoManual,
          diferenciaCentavos: diferenciaCentavos,
        ),
      );
    } on VentaCerradaException {
      _log.info(LogModulo.db, 'VENTA_CRECE_RECHAZADA', 'la venta ya no está abierta', {
        'venta_id': ventaId,
        'motivo': 'venta_cerrada',
      });
      return Left(FailureVentaCerrada(numeroTalonario: numeroTalonario));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros (el motivo). Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'VENTA_CRECE_FAIL',
        'no se pudo sumar a la venta',
        {'venta_id': ventaId, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureVentaNoGuardada(causa: tipo));
    }
  }
}
