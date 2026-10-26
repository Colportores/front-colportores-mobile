import 'package:equatable/equatable.dart';

/// Con quién fue (o va a ser) la entrevista: lo que el paso «¿Con quién?» de la vista 39 le entrega a
/// quien lo abrió (la entrevista en curso, #450). Lleva solo ids, nunca el nombre: la visita se
/// guarda contra el vínculo `espacio_persona` (`visita.espacio_persona_id`, ADR-017).
class PersonaDeLaEntrevista extends Equatable {
  const PersonaDeLaEntrevista({required this.personaId, required this.espacioPersonaId});

  /// `persona.id`.
  final String personaId;

  /// `espacio_persona.id`: el vínculo de la persona con el espacio (casa o depto) que se visita.
  final String espacioPersonaId;

  @override
  List<Object?> get props => [personaId, espacioPersonaId];
}
