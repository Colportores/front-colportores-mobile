import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/contexto_notas_persona.dart';
import '../../domain/entities/nota_persona.dart';
import '../../domain/repositories/nota_persona_repository.dart';
import '../datasources/nota_persona_local_data_source.dart';

/// Implementación de [NotaPersonaRepository] sobre [NotaPersonaLocalDataSource].
///
/// - Traduce el rechazo de la persistencia ([NotaRechazadaException]) a un `FailureValidacion` y
///   cualquier otra excepción a `FailureInesperado`; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el texto de la nota ni el nombre de
///   la persona (convenciones §7.5).
final class NotaPersonaRepositoryImpl implements NotaPersonaRepository {
  NotaPersonaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final NotaPersonaLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, NotaPersona>> agregar(NotaPersona nota) => _correr('NOTA_ALTA', {
    'nota_id': nota.id,
    'persona_id': nota.personaId,
  }, () => _local.agregar(nota));

  @override
  Future<Either<Failure, NotaPersona>> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  }) => _correr('NOTA_EDICION', {
    'nota_id': id,
  }, () => _local.editar(id: id, texto: texto, ahora: ahora));

  @override
  Future<Either<Failure, NotaPersona>> borrar({required String id, required DateTime ahora}) =>
      _correr('NOTA_BAJA', {'nota_id': id}, () => _local.borrar(id: id, ahora: ahora));

  @override
  Future<Either<Failure, NotaPersona>> restaurar({required String id, required DateTime ahora}) =>
      _correr('NOTA_RESTAURAR', {'nota_id': id}, () => _local.restaurar(id: id, ahora: ahora));

  @override
  Stream<List<NotaPersona>> observar(String personaId) => _local.observar(personaId);

  @override
  Future<Either<Failure, ContextoNotasPersona?>> leerContexto(String personaId) async {
    try {
      return Right(await _local.leerContexto(personaId));
    } on Object catch (e, st) {
      return Left(_inesperado('NOTA_CONTEXTO_FAIL', {'persona_id': personaId}, e, st));
    }
  }

  Future<Either<Failure, NotaPersona>> _correr(
    String operacion,
    Map<String, Object?> contexto,
    Future<NotaPersona> Function() accion,
  ) async {
    try {
      return Right(await accion());
    } on NotaRechazadaException catch (e) {
      _log.info(LogModulo.db, '${operacion}_RECHAZADA', 'operación sobre una nota rechazada', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      return Left(_inesperado('${operacion}_FAIL', contexto, e, st));
    }
  }

  /// Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
  /// parámetros, que acá son el texto de la nota (convenciones §7.5). Solo su tipo.
  Failure _inesperado(String operacion, Map<String, Object?> contexto, Object e, StackTrace st) {
    final tipo = e.runtimeType.toString();
    _log.error(
      LogModulo.db,
      operacion,
      'falló una operación sobre una nota',
      {...contexto, 'tipo': tipo},
      null,
      st,
    );
    return FailureInesperado(causa: tipo);
  }
}
