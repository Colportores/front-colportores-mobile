import 'package:equatable/equatable.dart';

import 'persona_de_la_entrevista.dart';

/// Con quién es la entrevista que se acaba de dar (vista 39, el paso «¿Con quién?» que sigue a
/// «Entrevista dada»). El nombre es **opcional** (decisión de Cristian, 04/11): la persona puede no
/// querer darlo y la entrevista sigue igual, sin persona; nunca se inventa a nadie.
sealed class EleccionDeEntrevista extends Equatable {
  const EleccionDeEntrevista();

  /// La persona de la entrevista, o `null` si queda sin persona.
  PersonaDeLaEntrevista? get persona;
}

/// La entrevista es con [persona].
final class EntrevistaConPersona extends EleccionDeEntrevista {
  const EntrevistaConPersona(this.persona);

  @override
  final PersonaDeLaEntrevista persona;

  @override
  List<Object?> get props => [persona];
}

/// La entrevista queda sin persona: la colportora tocó «Todavía no sé con quién».
final class EntrevistaSinPersona extends EleccionDeEntrevista {
  const EntrevistaSinPersona();

  @override
  PersonaDeLaEntrevista? get persona => null;

  @override
  List<Object?> get props => const [];
}
