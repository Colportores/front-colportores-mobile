import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/espacio_persona.dart';
import '../../domain/entities/estado_ubicacion_alternativa.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/repositories/ubicacion_alternativa_repository.dart';
import '../datasources/ubicacion_alternativa_local_data_source.dart';

/// Implementación de [UbicacionAlternativaRepository] sobre [UbicacionAlternativaLocalDataSource].
///
/// - Traduce el rechazo de la persistencia ([UbicacionAlternativaRechazadaException]) a un
///   `FailureValidacion` y cualquier otra excepción a `FailureInesperado`; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos (convenciones §7.5).
final class UbicacionAlternativaRepositoryImpl implements UbicacionAlternativaRepository {
  UbicacionAlternativaRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final UbicacionAlternativaLocalDataSource _local;
  final AppLogger _log;

  @override
  Stream<EstadoUbicacionAlternativa> observar({
    required String personaId,
    required String espacioId,
  }) => _local.observar(personaId: personaId, espacioId: espacioId);

  @override
  Stream<List<Ubicacion>> observarCandidatas({
    required String colportorId,
    required String espacioId,
  }) => _local.observarCandidatas(colportorId: colportorId, espacioId: espacioId);

  @override
  Future<Either<Failure, EspacioPersona>> establecer({
    required String personaId,
    required String espacioId,
    required String ubicacionId,
    required String colportorId,
    required DateTime ahora,
  }) => _escribir(
    'UBICACION_ALTERNATIVA_FIJAR',
    {'persona_id': personaId, 'espacio_id': espacioId, 'ubicacion_id': ubicacionId},
    () => _local.establecer(
      personaId: personaId,
      espacioId: espacioId,
      ubicacionId: ubicacionId,
      colportorId: colportorId,
      ahora: ahora,
    ),
  );

  @override
  Future<Either<Failure, EspacioPersona>> quitar({
    required String personaId,
    required String espacioId,
    required DateTime ahora,
  }) => _escribir(
    'UBICACION_ALTERNATIVA_QUITAR',
    {'persona_id': personaId, 'espacio_id': espacioId},
    () => _local.quitar(personaId: personaId, espacioId: espacioId, ahora: ahora),
  );

  Future<Either<Failure, EspacioPersona>> _escribir(
    String evento,
    Map<String, Object?> contexto,
    Future<EspacioPersona> Function() escribir,
  ) async {
    try {
      return Right(await escribir());
    } on UbicacionAlternativaRechazadaException catch (e) {
      _log.info(LogModulo.db, '${evento}_RECHAZADA', 'cambio de ubicación alternativa rechazado', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      // Solo el tipo: la excepción de Drift trae la sentencia con sus parámetros.
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló el cambio de ubicación alternativa',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureInesperado(causa: tipo));
    }
  }
}
