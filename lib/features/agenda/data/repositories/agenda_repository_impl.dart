import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/agenda.dart';
import '../../domain/entities/nota_de_campo.dart';
import '../../domain/entities/visita.dart';
import '../../domain/entities/visita_guardada.dart';
import '../../domain/repositories/agenda_repository.dart';
import '../datasources/agenda_local_data_source.dart';

/// Implementación de [AgendaRepository] sobre [AgendaLocalDataSource].
///
/// - Traduce el rechazo de la persistencia ([AgendaRechazadaException]) a un `FailureValidacion` y
///   cualquier otra excepción a `FailureInesperado`; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni la nota ni nada de la persona
///   (convenciones §7.5).
final class AgendaRepositoryImpl implements AgendaRepository {
  AgendaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AgendaLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) => _correr(
    'AGENDA_ALTA',
    {'agenda_id': agenda.id},
    () async => (await _local.agendar(agenda, nota: nota)).agenda,
  );

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) => _correr(
    'AGENDA_CANCELAR',
    {'agenda_id': agendaId},
    () async => (await _local.cancelar(agendaId, ahora: ahora)).agenda,
  );

  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) => _correr('VISITA_ALTA', {'visita_id': visita.id, 'agenda_id': ?agendaId}, () async {
    final r = await _local.registrarVisita(visita, agendaId: agendaId, nota: nota);
    if (r.agendaIgnorada case final motivo?) {
      _log.info(LogModulo.db, 'VISITA_ALTA_SIN_AGENDA', 'visita guardada sin su agenda', {
        'visita_id': r.visita.id,
        'agenda_id': ?agendaId,
        'motivo': motivo.name,
      });
    }
    return VisitaGuardada(
      visita: r.visita,
      agendaIgnorada: r.agendaIgnorada,
      agendaNoCumplida: r.agendaNoCumplida,
      agendaCreadaId: r.agendaCreadaId,
      agendaAfectadaId: r.agendaAfectadaId,
    );
  });

  @override
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId) => _correr(
    'AGENDA_PROGRAMADA',
    {'espacio_id': espacioId},
    () => _local.agendaProgramadaDe(espacioId),
  );

  @override
  Future<Either<Failure, Visita>> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) => _correr('VISITA_DESHACER', {'visita_id': visitaId}, () async {
    final r = await _local.deshacerVisita(
      visitaId,
      agendaCreadaId: agendaCreadaId,
      agendaAfectadaId: agendaAfectadaId,
      ahora: ahora,
    );
    return r.visita;
  });

  Future<Either<Failure, T>> _correr<T>(
    String evento,
    Map<String, Object?> contexto,
    Future<T> Function() operacion,
  ) async {
    try {
      return Right(await operacion());
    } on AgendaRechazadaException catch (e) {
      _log.info(LogModulo.db, '${evento}_RECHAZADA', 'operación de agenda rechazada', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló una operación de agenda',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureInesperado(causa: tipo));
    }
  }
}
