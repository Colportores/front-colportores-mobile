import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/cobranza.dart';
import '../../domain/entities/venta_con_saldo.dart';
import '../../domain/repositories/cobranza_repository.dart';
import '../datasources/cobranza_local_data_source_drift.dart';

/// Implementación de [CobranzaRepository] sobre [CobranzaLocalDataSourceDrift].
///
/// - Traduce el rechazo de la persistencia a su `Failure` (monto mayor al saldo, venta ausente, fecha
///   anterior a la venta) y cualquier otra excepción a [FailureCobroNoGuardado]; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el monto, ni nada de la persona
///   (convenciones §7.5).
final class CobranzaRepositoryImpl implements CobranzaRepository {
  CobranzaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final CobranzaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, CobroRegistrado>> registrar(Cobranza cobro) =>
      _correr('COBRO_ALTA', {'cobranza_id': cobro.id}, () => _local.registrar(cobro));

  @override
  Future<Either<Failure, VentaConSaldo?>> ventaConSaldo(String ventaId) =>
      _correr('COBRO_SALDO', {'venta_id': ventaId}, () => _local.ventaConSaldo(ventaId));

  @override
  Future<Either<Failure, List<VentaConSaldo>>> ventasConSaldoDe(String personaId) => _correr(
    'COBRO_VENTAS_CON_SALDO',
    {'persona_id': personaId},
    () => _local.ventasConSaldoDe(personaId),
  );

  Future<Either<Failure, T>> _correr<T>(
    String evento,
    Map<String, Object?> contexto,
    Future<T> Function() operacion,
  ) async {
    try {
      return Right(await operacion());
    } on CobroMayorAlSaldoException catch (e) {
      _log.info(LogModulo.db, '${evento}_RECHAZADO', 'mayor al saldo', {
        ...contexto,
        'motivo': 'mayor_al_saldo',
      });
      return Left(FailureCobroMayorAlSaldo(saldoCentavos: e.saldoCentavos));
    } on CobroSinVentaException {
      _log.info(LogModulo.db, '${evento}_RECHAZADO', 'venta ausente', {
        ...contexto,
        'motivo': 'venta',
      });
      return const Left(FailureCobroSinVenta());
    } on CobroFechaAnteriorException {
      _log.info(LogModulo.db, '${evento}_RECHAZADO', 'fecha anterior a la venta', {
        ...contexto,
        'motivo': 'fecha',
      });
      return const Left(FailureCobroFechaInvalida());
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló una operación de cobro',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureCobroNoGuardado(causa: tipo));
    }
  }
}
