/// Por qué la persistencia rechazó agendar, cancelar o registrar una visita (BACK-HU-VIS-001).
///
/// Los decide la capa `data` dentro de la transacción (donde puede leer el estado real de la DB) y
/// el repositorio los traduce a un `FailureValidacion` con el [campo] y el [mensaje] de acá. Los
/// mensajes dicen qué pasa y qué hacer; son textos **para confirmar** cuando llegue la pantalla.
enum MotivoRechazoAgenda {
  /// El vínculo persona ↔ espacio no está en el teléfono (o está dado de baja).
  personaInexistente('persona', 'No encontramos a esa persona en tu teléfono. Elegila de nuevo.'),

  /// La agenda no está en el teléfono (o está dada de baja).
  agendaInexistente(
    'agenda',
    'Esa agenda ya no está en tu teléfono. Volvé a la lista de agendados.',
  ),

  /// La agenda es de otra persona que la de la visita.
  agendaDeOtraPersona('agenda', 'Esa agenda es de otra persona. Elegí la agenda de esta visita.'),

  /// La agenda ya se cumplió o se canceló.
  agendaCerrada('agenda', 'Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.');

  const MotivoRechazoAgenda(this.campo, this.mensaje);

  /// Campo del formulario al que se asocia el mensaje.
  final String campo;

  final String mensaje;
}
