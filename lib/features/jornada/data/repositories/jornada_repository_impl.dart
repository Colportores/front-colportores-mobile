import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/jornada.dart';
import '../../domain/repositories/jornada_repository.dart';
import '../datasources/jornada_local_data_source.dart';
import '../models/jornada_model.dart';

/// Implementación de [JornadaRepository] sobre [JornadaLocalDataSource].
///
/// - Traduce toda excepción del almacenamiento a un [Failure]; nunca deja escapar una.
/// - Devuelve entidades de dominio (`toEntity()`), no modelos.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: `jornada` no tiene PII.
///
/// TODO(#70): encolar el sync. Según contrato-sync-engine.md §3 la escritura local y el
/// `engine.stage(Tables.jornada, Op.insert, modelo.toJson())` van en la misma transacción, con
/// `SyncSpec.push(Tables.jornada, critical: true)` (§2). El motor (`sync_engine`, PR #40) y su
/// cola sobre la DB (PR #41) todavía no están en `develop`; se engancha acá cuando entren. La
/// tabla `jornada` ya existe (`JornadaLocalDataSourceDrift`).
final class JornadaRepositoryImpl implements JornadaRepository {
  JornadaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final JornadaLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, Jornada?>> obtenerActiva(String colportorId) async {
    try {
      final activa = await _local.obtenerActiva(colportorId);
      return Right(activa?.toEntity());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'JORNADA_LEER_FAIL',
        'no se pudo leer la jornada activa',
        {'user_id': colportorId},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Jornada>> crear(Jornada jornada) async {
    final modelo = JornadaModel.fromEntity(jornada);
    try {
      await _local.insertar(modelo);
      _log.info(LogModulo.db, 'JORNADA_INICIADA', 'jornada iniciada', {
        'jornada_id': jornada.id,
        'user_id': jornada.colportorId,
      });
      return Right(modelo.toEntity());
    } on JornadaActivaExistenteException {
      const failure = FailureJornadaActiva();
      _log.warn(LogModulo.db, 'JORNADA_INICIO_RECHAZADO', 'ya hay una jornada en curso', {
        'user_id': jornada.colportorId,
        'codigo': failure.codigo,
      });
      return const Left(failure);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'JORNADA_INICIO_FAIL',
        'no se pudo guardar la jornada',
        {'jornada_id': jornada.id},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }
}
