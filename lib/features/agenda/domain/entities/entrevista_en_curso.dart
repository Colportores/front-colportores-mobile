import 'package:equatable/equatable.dart';

import '../../../../core/domain/instante.dart';
import '../usecases/registrar_resultado_visita_use_case.dart' show IdsResultadoVisita;

/// Una entrevista que la colportora empezó con «Empezar» y todavía no terminó (vista 39, R·05;
/// HU-VIS-005). Vive en el teléfono hasta «Finalizar»: salir de la hoja, ir a la agenda o cerrar la
/// app no la termina (decisión de Cristian, 23/10, front-colportores-mobile#450, «Entrevista
/// fuera»).
///
/// **Solo ids y la hora de inicio**, nunca nombres ni direcciones: la dirección y el nombre de la
/// persona se leen de la DB cuando hacen falta. La nota del borrador tampoco vive acá.
class EntrevistaEnCurso extends Equatable {
  EntrevistaEnCurso({
    required this.colportorId,
    required this.espacioId,
    required this.espacioPersonaId,
    required this.ids,
    required DateTime inicio,
    this.agendaId,
    this.jornadaId,
  }) : inicio = instanteMs(inicio);

  final String colportorId;

  /// El espacio (casa, depto o negocio) donde es la entrevista.
  final String espacioId;

  /// Con quién (`espacio_persona.id`): lo pide la visita (`NOT NULL` en el servidor).
  final String espacioPersonaId;

  /// Los ids de la visita y su nota, generados **una vez** al empezar: un reintento al guardar
  /// repite los mismos y no duplica la visita.
  final IdsResultadoVisita ids;

  /// El toque de «Empezar», en UTC y al milisegundo. No se pierde ni se pisa.
  final DateTime inicio;

  /// La agenda que la entrevista viene a cumplir, si la casa tenía una.
  final String? agendaId;

  /// La jornada abierta cuando empezó, si la había.
  final String? jornadaId;

  @override
  List<Object?> get props => [
    colportorId,
    espacioId,
    espacioPersonaId,
    ids,
    inicio,
    agendaId,
    jornadaId,
  ];
}
