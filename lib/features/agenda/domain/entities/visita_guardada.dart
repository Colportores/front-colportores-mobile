import 'package:equatable/equatable.dart';

import 'visita.dart';

/// Por qué una visita se guardó **sin** la agenda que la pantalla le había indicado.
///
/// Una visita no se pierde porque su agenda ya no sirva (decisión de Cristian/mapa §2, QA de #404):
/// se guarda como visita espontánea (con su agenda cumplida) y se avisa. Los [aviso]s son textos
/// **para confirmar** cuando llegue la pantalla de la agenda (vista 23).
enum MotivoAgendaIgnorada {
  /// La agenda ya se cumplió, no se cumplió o se canceló: no se toca.
  cerrada('Esa agenda ya estaba cerrada: guardamos la visita igual, como visita espontánea.'),

  /// La agenda no está en el teléfono (o está dada de baja).
  inexistente(
    'Esa agenda ya no está en tu teléfono: guardamos la visita igual, como visita espontánea.',
  ),

  /// La agenda es de otra casa o depto que la visita: no se toca.
  deOtraCasa('Esa agenda es de otra casa: guardamos la visita igual, como visita espontánea.'),

  /// La agenda es de otra persona que la de la visita: no se toca.
  deOtraPersona(
    'Esa agenda es de otra persona: guardamos la visita igual, como visita espontánea.',
  );

  const MotivoAgendaIgnorada(this.aviso);

  /// Lo que se le muestra a la colportora: qué pasó y que la visita quedó guardada.
  final String aviso;
}

/// El resultado de registrar una visita: la [visita] guardada y, si la agenda que se quería
/// cumplir no sirvió, por qué se guardó sin ella ([agendaIgnorada]).
final class VisitaGuardada extends Equatable {
  const VisitaGuardada({
    required this.visita,
    this.agendaIgnorada,
    this.agendaNoCumplida = false,
    this.agendaCreadaId,
    this.agendaAfectadaId,
  });

  final Visita visita;

  /// `null` si no había agenda, o si la visita cumplió (o no cumplió) la que se indicó.
  final MotivoAgendaIgnorada? agendaIgnorada;

  /// `true` si la agenda indicada sirve pero el resultado no la cumple (`NO_CONTESTO`): la visita se
  /// guardó y la agenda pasó a `NO_CUMPLIDA` (decisión del 23/10, «No cumplida»). Nunca es `true`
  /// junto con [agendaIgnorada].
  final bool agendaNoCumplida;

  /// La agenda que creó la visita espontánea (ya `CUMPLIDA`), si la creó. Para deshacer.
  final String? agendaCreadaId;

  /// La agenda existente que la visita cumplió o no cumplió, si la había. Para deshacer.
  final String? agendaAfectadaId;

  /// El aviso para la pantalla, o `null` si no hay nada que avisar.
  String? get aviso => agendaIgnorada?.aviso;

  @override
  List<Object?> get props => [
    visita,
    agendaIgnorada,
    agendaNoCumplida,
    agendaCreadaId,
    agendaAfectadaId,
  ];
}
