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
/// El sync lo encola el data source, tanto el alta ([crear]) como el cierre ([finalizar]), en la
/// misma transacción que la escritura (`JornadaLocalDataSourceDrift`, contrato-sync-engine §3):
/// una jornada guardada siempre tiene su job en la cola, y si el job no entra no se guarda nada.
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

  @override
  Future<Either<Failure, Jornada?>> siguienteA(Jornada jornada) async {
    try {
      final siguiente = await _local.siguienteA(
        colportorId: jornada.colportorId,
        inicio: jornada.inicio,
      );
      return Right(siguiente?.toEntity());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'JORNADA_SIGUIENTE_FAIL',
        'no se pudo leer la jornada siguiente',
        {'jornada_id': jornada.id},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Jornada>> finalizar(Jornada jornada) async {
    final modelo = JornadaModel.fromEntity(jornada);
    try {
      await _local.finalizar(modelo);
      _log.info(LogModulo.db, 'JORNADA_FINALIZADA', 'jornada finalizada', {
        'jornada_id': jornada.id,
        'user_id': jornada.colportorId,
      });
      return Right(modelo.toEntity());
    } on JornadaNoAbiertaException {
      const failure = FailureSinJornadaActiva();
      _log.warn(LogModulo.db, 'JORNADA_FIN_RECHAZADO', 'la jornada ya no estaba abierta', {
        'jornada_id': jornada.id,
        'codigo': failure.codigo,
      });
      return const Left(failure);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'JORNADA_FIN_FAIL',
        'no se pudo guardar el fin de la jornada',
        {'jornada_id': jornada.id},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }
}
