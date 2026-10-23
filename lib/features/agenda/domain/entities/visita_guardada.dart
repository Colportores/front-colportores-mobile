import 'package:equatable/equatable.dart';

import 'visita.dart';

/// Por qué una visita se guardó **sin** la agenda que la pantalla le había indicado.
///
/// Una visita no se pierde porque su agenda ya no sirva (decisión de Cristian/mapa §2, QA de #404):
/// se guarda como visita espontánea (con su agenda cumplida) y se avisa. Los [aviso]s son textos **para confirmar** cuando
/// llegue la pantalla (vista 23, #410).
enum MotivoAgendaIgnorada {
  /// La agenda ya se cumplió o se canceló: no se toca.
  cerrada('Esa agenda ya estaba cerrada: guardamos la visita igual, como visita espontánea.'),

  /// La agenda no está en el teléfono (o está dada de baja).
  inexistente(
    'Esa agenda ya no está en tu teléfono: guardamos la visita igual, como visita espontánea.',
  ),

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
    this.agendaQuedoPendiente = false,
  });

  /// Texto **para confirmar** cuando llegue la pantalla (vista 39): la visita se guardó y la agenda
  /// sigue esperando, con qué hacer.
  static const avisoAgendaPendiente =
      'Guardamos la visita. La agenda sigue pendiente porque todavía no se puede marcar como no '
      'cumplida: si ya no va, cancelala desde Agendados.';

  final Visita visita;

  /// `null` si no había agenda, o si la visita cumplió la que se indicó.
  final MotivoAgendaIgnorada? agendaIgnorada;

  /// `true` si la agenda indicada sirve pero el resultado no la cumple (`NO_CONTESTO`): la visita se
  /// guardó y la agenda sigue `PENDIENTE`, sin tocar (pendiente P1 de #151: «no cumplida» no existe
  /// en el servidor). Nunca es `true` junto con [agendaIgnorada].
  final bool agendaQuedoPendiente;

  /// El aviso para la pantalla, o `null` si no hay nada que avisar.
  String? get aviso =>
      agendaIgnorada?.aviso ?? (agendaQuedoPendiente ? avisoAgendaPendiente : null);

  @override
  List<Object?> get props => [visita, agendaIgnorada, agendaQuedoPendiente];
}
