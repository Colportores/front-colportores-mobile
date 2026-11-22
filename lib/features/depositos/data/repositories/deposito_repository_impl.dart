import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/deposito.dart';
import '../../domain/entities/totales_de_depositos.dart';
import '../../domain/repositories/deposito_repository.dart';
import '../datasources/deposito_local_data_source_drift.dart';

/// Implementación de [DepositoRepository] sobre [DepositoLocalDataSourceDrift].
///
/// - Traduce el rechazo de la persistencia a su `Failure` (ticket ya usado) y cualquier otra
///   excepción a [FailureDepositoNoGuardado]; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el monto, ni nada más
///   (convenciones §7.5).
final class DepositoRepositoryImpl implements DepositoRepository {
  DepositoRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final DepositoLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, DepositoRegistrado>> registrar(Deposito deposito) async {
    try {
      return Right(await _local.registrar(deposito));
    } on DepositoTicketYaUsadoException {
      _log.info(LogModulo.db, 'DEPOSITO_ALTA_RECHAZADO', 'ticket ya usado', {
        'deposito_id': deposito.id,
        'motivo': 'ticket_ya_usado',
      });
      return const Left(FailureDepositoTicketYaUsado());
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'DEPOSITO_ALTA_FAIL',
        'falló el registro de un depósito',
        {'deposito_id': deposito.id, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureDepositoNoGuardado(causa: tipo));
    }
  }

  @override
  Future<Either<Failure, List<Deposito>>> todos() async {
    try {
      return Right(await _local.todos());
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'DEPOSITO_LECTURA_FAIL',
        'falló la lectura de los depósitos',
        {'tipo': tipo},
        null,
        st,
      );
      return const Left(FailureDepositoNoDisponible());
    }
  }

  @override
  Stream<List<Deposito>> observar() => _local.observar().handleError((Object error, StackTrace st) {
    _log.error(
      LogModulo.db,
      'DEPOSITO_STREAM_FAIL',
      'falló la lectura de los depósitos',
      {'tipo': error.runtimeType.toString()},
      null,
      st,
    );
    throw const FailureDepositoNoDisponible();
  });

  @override
  Future<Either<Failure, TotalesDeDepositos>> totales() async {
    try {
      return Right(await _local.totales());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'DEPOSITO_TOTALES_FAIL',
        'falló la suma de los depósitos',
        {'tipo': e.runtimeType.toString()},
        null,
        st,
      );
      return const Left(FailureDepositoNoDisponible());
    }
  }
}
