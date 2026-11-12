import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/contexto_edicion_persona.dart';
import '../../domain/entities/espacio_persona.dart';
import '../../domain/entities/nota_persona.dart';
import '../../domain/entities/persona.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../../domain/repositories/persona_repository.dart';
import '../datasources/persona_local_data_source.dart';

/// Implementación de [PersonaRepository] sobre [PersonaLocalDataSource].
///
/// - Traduce el rechazo de la persistencia ([PersonaRechazadaException]) a un `FailureValidacion` y
///   cualquier otra excepción a `FailureInesperado`; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el nombre, ni el teléfono, ni la
///   nota (convenciones §7.5).
final class PersonaRepositoryImpl implements PersonaRepository {
  PersonaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final PersonaLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, Persona>> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  }) async {
    final contexto = {'persona_id': persona.id, 'espacio_id': vinculo.espacioId};
    try {
      final registro = await _local.registrar(persona: persona, vinculo: vinculo, nota: nota);
      return Right(registro.persona);
    } on PersonaRechazadaException catch (e) {
      _log.info(LogModulo.db, 'PERSONA_ALTA_RECHAZADA', 'alta de persona rechazada', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros, que acá son el nombre, el teléfono y la nota (convenciones §7.5). Solo su tipo.
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        'PERSONA_ALTA_FAIL',
        'falló el alta de persona',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureInesperado(causa: tipo));
    }
  }

  @override
  Future<Either<Failure, ContextoEdicionPersona?>> leerParaEditar(String personaId) async {
    try {
      return Right(await _local.leerParaEditar(personaId));
    } on Object catch (e, st) {
      return Left(_inesperado('PERSONA_LECTURA_FAIL', {'persona_id': personaId}, e, st));
    }
  }

  @override
  Future<Either<Failure, ResultadoModificarPersona>> modificar({
    required String personaId,
    required String nombre,
    required String apellido,
    required String? telefono,
    required DateTime ahora,
  }) async {
    final contexto = {'persona_id': personaId};
    try {
      return Right(
        await _local.modificar(
          personaId: personaId,
          nombre: nombre,
          apellido: apellido,
          telefono: telefono,
          ahora: ahora,
        ),
      );
    } on PersonaRechazadaException catch (e) {
      _log.info(LogModulo.db, 'PERSONA_EDICION_RECHAZADA', 'edición de persona rechazada', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      return Left(_inesperado('PERSONA_EDICION_FAIL', contexto, e, st));
    }
  }

  /// Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
  /// parámetros, que acá son el nombre y el teléfono (convenciones §7.5). Solo su tipo.
  Failure _inesperado(String operacion, Map<String, Object?> contexto, Object e, StackTrace st) {
    final tipo = e.runtimeType.toString();
    _log.error(
      LogModulo.db,
      operacion,
      'falló una operación sobre una persona',
      {...contexto, 'tipo': tipo},
      null,
      st,
    );
    return FailureInesperado(causa: tipo);
  }

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) =>
      _local.observarDelEspacio(espacioId);

  @override
  Stream<List<PersonaDelEspacio>> observarBajasDelEspacio(String espacioId) =>
      _local.observarBajasDelEspacio(espacioId);

  @override
  Future<Either<Failure, Persona>> darDeBaja({
    required String personaId,
    required DateTime ahora,
    String? motivo,
  }) => _escribir(
    'PERSONA_BAJA',
    personaId,
    () => _local.darDeBaja(personaId: personaId, ahora: ahora, motivo: motivo),
  );

  @override
  Future<Either<Failure, Persona>> reactivar({
    required String personaId,
    required DateTime ahora,
  }) => _escribir(
    'PERSONA_REACTIVAR',
    personaId,
    () => _local.reactivar(personaId: personaId, ahora: ahora),
  );

  /// Una escritura sobre una persona que ya existe: traduce el rechazo de la persistencia a un
  /// `FailureValidacion` y cualquier otra excepción a `FailureInesperado`. Al log va solo el id y el
  /// tipo (convenciones §7.5): ni el nombre, ni el teléfono, ni el motivo.
  Future<Either<Failure, Persona>> _escribir(
    String evento,
    String personaId,
    Future<Persona> Function() escribir,
  ) async {
    final contexto = {'persona_id': personaId};
    try {
      return Right(await escribir());
    } on PersonaRechazadaException catch (e) {
      _log.info(LogModulo.db, '${evento}_RECHAZADA', 'escritura de persona rechazada', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló una escritura de persona',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureInesperado(causa: tipo));
    }
  }
}
