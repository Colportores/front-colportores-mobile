import 'package:equatable/equatable.dart';

import 'persona_de_la_entrevista.dart';

/// Con quién se programa una entrevista (vista 39, el paso «¿Con quién es la entrevista?» que sigue a
/// «Programar entrevista»). A diferencia de la entrevista que ya se dio, la cita puede quedar **sin
/// persona**: todavía no se sabe con quién (decisión «Sin persona», 23/10).
sealed class EleccionDeCita extends Equatable {
  const EleccionDeCita();

  /// El vínculo `espacio_persona.id` de la cita, o `null` si queda sin persona.
  String? get espacioPersonaId;

  @override
  List<Object?> get props => [espacioPersonaId];
}

/// La cita es con [persona].
final class CitaConPersona extends EleccionDeCita {
  const CitaConPersona(this.persona);

  final PersonaDeLaEntrevista persona;

  @override
  String? get espacioPersonaId => persona.espacioPersonaId;

  @override
  List<Object?> get props => [persona];
}

/// La cita queda sin persona: la casa no tiene a nadie cargado o la colportora todavía no sabe con quién.
final class CitaSinPersona extends EleccionDeCita {
  const CitaSinPersona();

  @override
  String? get espacioPersonaId => null;
}
