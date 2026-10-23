import 'package:equatable/equatable.dart';

import 'visita.dart';

/// Por qué una visita se guardó **sin** la agenda que la pantalla le había indicado.
///
/// Una visita no se pierde porque su agenda ya no sirva (decisión de Cristian/mapa §2, QA de #404):
/// se guarda como visita espontánea y se avisa. Los [aviso]s son textos **para confirmar** cuando
/// llegue la pantalla (vista 23, #410).
enum MotivoAgendaIgnorada {
  /// La agenda ya se cumplió o se canceló: no se toca.
  cerrada('Esa agenda ya estaba cerrada: guardamos la visita igual, sin agenda.'),

  /// La agenda no está en el teléfono (o está dada de baja).
  inexistente('Esa agenda ya no está en tu teléfono: guardamos la visita igual, sin agenda.'),

  /// La agenda es de otra persona que la de la visita: no se toca.
  deOtraPersona('Esa agenda es de otra persona: guardamos la visita igual, sin agenda.');

  const MotivoAgendaIgnorada(this.aviso);

  /// Lo que se le muestra a la colportora: qué pasó y que la visita quedó guardada.
  final String aviso;
}

/// El resultado de registrar una visita: la [visita] guardada y, si la agenda que se quería
/// cumplir no sirvió, por qué se guardó sin ella ([agendaIgnorada]).
final class VisitaGuardada extends Equatable {
  const VisitaGuardada({required this.visita, this.agendaIgnorada});

  final Visita visita;

  /// `null` si no había agenda, o si la visita cumplió la que se indicó.
  final MotivoAgendaIgnorada? agendaIgnorada;

  /// El aviso para la pantalla, o `null` si no hay nada que avisar.
  String? get aviso => agendaIgnorada?.aviso;

  @override
  List<Object?> get props => [visita, agendaIgnorada];
}
