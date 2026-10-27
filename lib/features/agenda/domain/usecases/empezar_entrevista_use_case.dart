import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/entrevista_en_curso.dart';
import '../repositories/entrevista_en_curso_repository.dart';
import 'registrar_resultado_visita_use_case.dart' show IdsResultadoVisita;

/// Parámetros de [EmpezarEntrevistaUseCase].
final class EmpezarEntrevistaParams extends Equatable {
  const EmpezarEntrevistaParams({
    required this.colportorId,
    required this.espacioId,
    required this.espacioPersonaId,
    this.agendaId,
    this.jornadaId,
  });

  final String colportorId;
  final String espacioId;
  final String espacioPersonaId;
  final String? agendaId;
  final String? jornadaId;

  @override
  List<Object?> get props => [colportorId, espacioId, espacioPersonaId, agendaId, jornadaId];
}

/// HU-VIS-005, vista 39 R·04 → R·05: «Empezar entrevista». Guarda la entrevista en curso **en el
/// teléfono** con la hora del toque, y devuelve esa misma entrevista.
///
/// - Si la colportora **ya tiene una en curso** (doble toque, o volvió a «Empezar» sin terminar la
///   anterior), devuelve **la que estaba**: la hora de inicio no se pisa ni se pierde. La pantalla
///   decide qué le dice.
/// - Sin colportora, espacio o persona no guarda nada: `Left(FailureValidacion)`.
/// - Si el almacén falla, `Left` y no hay entrevista en curso: la hora no queda a medias.
final class EmpezarEntrevistaUseCase
    implements UseCase<EntrevistaEnCurso, EmpezarEntrevistaParams> {
  EmpezarEntrevistaUseCase(
    this._repository, {
    required this._generarId,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final EntrevistaEnCursoRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Future<Either<Failure, EntrevistaEnCurso>> call(EmpezarEntrevistaParams params) async {
    final colportorId = params.colportorId.trim();
    final espacioId = params.espacioId.trim();
    final espacioPersonaId = params.espacioPersonaId.trim();
    final campos = <String, String>{
      if (colportorId.isEmpty) 'colportorId': 'No hay un colportor para empezar la entrevista',
      if (espacioId.isEmpty) 'espacioId': 'Falta el lugar de la entrevista',
      if (espacioPersonaId.isEmpty) 'persona': 'Elegí con quién es la entrevista para empezarla.',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    try {
      final enCurso = await _repository.leer(colportorId);
      if (enCurso != null) return Right(enCurso);

      final agendaId = params.agendaId?.trim();
      final jornadaId = params.jornadaId?.trim();
      final entrevista = EntrevistaEnCurso(
        colportorId: colportorId,
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId,
        ids: IdsResultadoVisita(visita: _generarId(), nota: _generarId()),
        inicio: _ahora(),
        agendaId: agendaId == null || agendaId.isEmpty ? null : agendaId,
        jornadaId: jornadaId == null || jornadaId.isEmpty ? null : jornadaId,
      );
      await _repository.guardar(entrevista);
      return Right(entrevista);
    } on Object catch (e) {
      _log.error(
        LogModulo.agenda,
        'ENTREVISTA_EMPEZAR',
        'no se pudo guardar la entrevista en curso',
        {'tipo': e.runtimeType.toString()},
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }
}
