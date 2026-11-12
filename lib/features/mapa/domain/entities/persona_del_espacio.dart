import 'package:equatable/equatable.dart';

import 'espacio_persona.dart';
import 'persona.dart';

/// Una persona tal como la lista un espacio: ella y su vínculo con él (`espacio_persona`).
class PersonaDelEspacio extends Equatable {
  const PersonaDelEspacio({required this.persona, required this.vinculo});

  final Persona persona;
  final EspacioPersona vinculo;

  /// Lleva datos personales: ver `Persona.stringify`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [persona, vinculo];
}
