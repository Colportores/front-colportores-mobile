import 'package:equatable/equatable.dart';

/// A qué casa (o depto) y a qué persona se guarda hoy una entrevista que empezó antes: lo que
/// [DestinoDeEntrevista.resolver] encuentra en el teléfono, que puede no ser lo que tenía al empezar.
final class DestinoDeEntrevista extends Equatable {
  const DestinoDeEntrevista({required this.espacioId, this.espacioPersonaId});

  /// El espacio vivo donde queda la visita.
  final String espacioId;

  /// El vínculo con la persona, o `null` si la persona ya no está (visita «Sin persona»).
  final String? espacioPersonaId;

  @override
  List<Object?> get props => [espacioId, espacioPersonaId];
}

/// «Sin salida» (vista 39, decisión de Cristian del 25/10, front-colportores-mobile#450): entre que
/// la colportora empezó la entrevista y la termina, la persona o el lugar pueden haber cambiado en
/// el teléfono (una unión de duplicados, una baja que llegó por sync). La visita **se guarda igual**:
///
/// - persona unida a otra: la visita va a la que quedó (el vínculo sigue su camino);
/// - persona dada de baja (o sin su fila): la visita queda de la casa o del depto, sin persona;
/// - casa o depto unido a otro: la visita va al que quedó.
abstract interface class ResolverDestinoDeEntrevista {
  /// El destino vivo de la entrevista que empezó en [espacioId] con [espacioPersonaId], o `null` si
  /// ya no hay dónde colgar la visita (ni el espacio ni el vínculo siguen en el teléfono).
  Future<DestinoDeEntrevista?> resolver({
    required String espacioId,
    required String espacioPersonaId,
  });
}
