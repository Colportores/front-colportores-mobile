import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/repositories/pares_duplicados_repository.dart';
import '../datasources/pares_duplicados_local_data_source.dart';

/// Implementación de [ParesDuplicadosRepository] sobre [ParesDuplicadosLocalDataSource].
///
/// Traduce toda excepción a un [Failure]. Cada decisión deja un log `[DB]` con los `id`, la
/// decisión y el motivo del par (sin direcciones): de ahí sale la métrica de falsos positivos de
/// R21 ("Conservar ambos" sobre cuántos pares).
final class ParesDuplicadosRepositoryImpl implements ParesDuplicadosRepository {
  ParesDuplicadosRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final ParesDuplicadosLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, Map<String, ParDecidido>>> decididos() async {
    try {
      return Right(await _local.decididos());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'UBICACION_PARES_LEER_FAIL',
        'no se pudieron leer los pares decididos',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Stream<Map<String, ParDecidido>> observarDecididos() => _local.observarDecididos();

  @override
  Future<Either<Failure, Unit>> decidir(
    ParDuplicado par,
    DecisionParDuplicado decision, {
    required DateTime ahora,
  }) async {
    final datos = {
      'ubicacion_a_id': par.a.id,
      'ubicacion_b_id': par.b.id,
      'decision': decision.name,
      'motivo': par.motivo.name,
    };
    try {
      await _local.decidir(par.a.id, par.b.id, decision, decididoEn: ahora);
      _log.info(LogModulo.db, 'UBICACION_PAR_DECIDIDO', 'par de posibles duplicados', datos);
      return const Right(unit);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'UBICACION_PAR_DECIDIR_FAIL',
        'no se pudo guardar la decisión del par',
        datos,
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }
}
