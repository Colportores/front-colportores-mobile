import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/entities/entrega_diferida.dart';
import '../../domain/entities/entrega_pendiente.dart';
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

  @override
  Future<Either<Failure, EntregaDiferida>> diferir(
    String ventaId, {
    required DateTime fechaPrevista,
    required DateTime ahora,
    required List<Entrega> filasNuevas,
    required String idDeLaCita,
  }) async {
    try {
      return Right(
        await _local.diferir(
          ventaId,
          fechaPrevista: fechaPrevista,
          ahora: ahora,
          filasNuevas: filasNuevas,
          idDeLaCita: idDeLaCita,
        ),
      );
    } on EntregaSinPendientesException catch (e) {
      return Left(
        FailureValidacion(campos: {'entrega': e.sinFilas ? _sinProductos : _yaEntregada}),
      );
    } on EntregaSinVentaException {
      return Left(
        _rechazada('ENTREGA_DIFERIDA_RECHAZADA', ventaId, 'venta', 'EntregaSinVentaException'),
      );
    } on EntregaSinCasaException {
      return Left(
        _rechazada('ENTREGA_DIFERIDA_RECHAZADA', ventaId, 'casa', 'EntregaSinCasaException'),
      );
    } on Object catch (e, st) {
      return Left(
        _fallo('ENTREGA_DIFERIDA_FAIL', 'falló la entrega para otro día', ventaId, e, st),
      );
    }
  }

  @override
  Future<Either<Failure, EntregaCumplida>> cumplir(
    String ventaId, {
    required DateTime ahora,
    required String idDeLaCita,
    Set<String>? entregaIds,
    DateTime? nuevaFecha,
  }) async {
    try {
      return Right(
        await _local.cumplir(
          ventaId,
          ahora: ahora,
          idDeLaCita: idDeLaCita,
          entregaIds: entregaIds,
          nuevaFecha: nuevaFecha,
        ),
      );
    } on EntregaSinPendientesException catch (e) {
      return Left(
        FailureValidacion(campos: {'entrega': e.sinFilas ? _sinEntregas : _nadaPendiente}),
      );
    } on EntregaAjenaException {
      return const Left(FailureValidacion(campos: {'productos': _productoAjeno}));
    } on EntregaSinVentaException {
      return Left(
        _rechazada('ENTREGA_CUMPLIR_RECHAZADA', ventaId, 'venta', 'EntregaSinVentaException'),
      );
    } on Object catch (e, st) {
      return Left(_fallo('ENTREGA_CUMPLIR_FAIL', 'falló marcar la entrega', ventaId, e, st));
    }
  }

  @override
  Stream<List<EntregaPendiente>> observarPendientes({String? espacioPersonaId}) =>
      _local.observarPendientes(espacioPersonaId: espacioPersonaId);

  // Textos a confirmar (el canvas no dibuja estos errores): dicen qué pasó y qué hacer.
  static const _yaEntregada = 'Esa venta ya está entregada: no queda nada pendiente.';
  static const _sinProductos = 'Elegí al menos un producto para dejar para otro día.';
  static const _sinEntregas = 'Esa venta no tiene entregas pendientes.';
  static const _nadaPendiente = 'No queda nada pendiente de entregar en esa venta.';
  static const _productoAjeno =
      'Alguno de los productos no es de esa venta. Volvé a abrir la entrega.';

  Failure _rechazada(String evento, String ventaId, String motivo, String causa) {
    _log.info(LogModulo.db, evento, 'rechazada', {'venta_id': ventaId, 'motivo': motivo});
    return FailureEntregaNoGuardada(causa: causa);
  }

  Failure _fallo(String evento, String mensaje, String ventaId, Object e, StackTrace st) {
    // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
    // parámetros. Solo su tipo (convenciones §7.5).
    final tipo = e.runtimeType.toString();
    _log.error(LogModulo.db, evento, mensaje, {'venta_id': ventaId, 'tipo': tipo}, null, st);
    return FailureEntregaNoGuardada(causa: tipo);
  }
}
