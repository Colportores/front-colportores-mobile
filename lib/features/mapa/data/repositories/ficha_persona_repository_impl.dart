import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/repositories/ficha_persona_repository.dart';
import '../datasources/ficha_persona_local_data_source_drift.dart';

/// [FichaPersonaRepository] sobre [FichaPersonaLocalDataSourceDrift].
///
/// - La lectura sale tal cual: un error de la base sale por el `Stream`.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el nombre, ni el teléfono
///   (convenciones §7.5).
final class FichaPersonaRepositoryImpl implements FichaPersonaRepository {
  FichaPersonaRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final FichaPersonaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Stream<LecturaDeFicha?> observar(String personaId) => _local.observar(personaId);

  @override
  Future<Either<Failure, Unit>> registrarLlamada({
    required String personaId,
    required DateTime ahora,
  }) async {
    try {
      await _local.registrarLlamada(personaId: personaId, ahora: ahora);
      return const Right(unit);
    } on Object catch (e, st) {
      // Solo el tipo: la excepción de Drift trae la sentencia con sus parámetros (§7.5).
      _log.error(
        LogModulo.db,
        'FICHA_LLAMADA_FAIL',
        'no se pudo registrar la llamada',
        {'persona_id': personaId, 'tipo': e.runtimeType.toString()},
        null,
        st,
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }
}
