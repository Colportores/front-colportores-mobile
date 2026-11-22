import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/repositories/limpieza_notas_borradas_repository.dart';
import '../datasources/notas_borradas_local_data_source_drift.dart';

/// [LimpiezaNotasBorradasRepository] sobre [NotasBorradasLocalDataSourceDrift].
///
/// Nunca deja escapar una excepción. Loguea en `[DB]` solo cuántas notas borró y el tipo de la falla:
/// ni el texto de una nota ni la excepción de Drift, que trae la sentencia (convenciones §7.5).
final class LimpiezaNotasBorradasRepositoryImpl implements LimpiezaNotasBorradasRepository {
  LimpiezaNotasBorradasRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final NotasBorradasLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, int>> purgarVencidas({required DateTime ahora}) async {
    try {
      final borradas = await _local.purgarVencidas(ahora: ahora);
      if (borradas > 0) {
        _log.info(LogModulo.db, 'NOTAS_BORRADAS_PURGA', 'se borraron notas con más de 90 días', {
          'cantidad': borradas,
        });
      }
      return Right(borradas);
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'NOTAS_BORRADAS_PURGA_FAIL',
        'no se pudieron limpiar las notas borradas',
        {'tipo': tipo},
        null,
        st,
      );
      return Left(FailureInesperado(causa: tipo));
    }
  }
}
