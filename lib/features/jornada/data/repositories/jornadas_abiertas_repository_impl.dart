import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/jornada.dart';
import '../../domain/repositories/jornadas_abiertas_repository.dart';
import '../datasources/jornada_local_data_source.dart';

/// Lee todas las jornadas abiertas del colportor del mismo almacenamiento que usa la jornada en
/// curso. Un almacenamiento que no sabe listarlas (solo lo son los dobles de los tests de otras
/// pantallas) dice que no hay ninguna.
final class JornadasAbiertasRepositoryImpl implements JornadasAbiertasRepository {
  JornadasAbiertasRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final JornadaLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, List<Jornada>>> abiertas(String colportorId) async {
    final Object local = _local;
    if (local is! JornadasAbiertasDataSource) return const Right([]);
    try {
      final abiertas = await local.abiertas(colportorId);
      return Right([for (final jornada in abiertas) jornada.toEntity()]);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'JORNADA_ABIERTAS_FAIL',
        'no se pudieron leer las jornadas abiertas',
        {'user_id': colportorId},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }
}
