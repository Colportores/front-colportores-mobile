/// Por qué la persistencia rechazó agendar, cancelar o registrar una visita (BACK-HU-VIS-001).
///
/// Los decide la capa `data` dentro de la transacción (donde puede leer el estado real de la DB) y
/// el repositorio los traduce a un `FailureValidacion` con el [campo] y el [mensaje] de acá. Los
/// mensajes dicen qué pasa y qué hacer; son textos **para confirmar** cuando llegue la pantalla.
enum MotivoRechazoAgenda {
  /// El espacio (la casa o el depto) no está en el teléfono (o está dado de baja).
  espacioInexistente(
    'espacio',
    'No encontramos esa casa en tu teléfono. Volvé al mapa y elegila de nuevo.',
  ),

  /// El vínculo persona ↔ espacio no está en el teléfono (o está dado de baja, o es de otra casa).
  personaInexistente('persona', 'No encontramos a esa persona en tu teléfono. Elegila de nuevo.'),

  /// La visita no está en el teléfono.
  visitaInexistente('visita', 'Esa visita ya no está en tu teléfono.'),

  /// La agenda no está en el teléfono (o está dada de baja).
  agendaInexistente(
    'agenda',
    'Esa agenda ya no está en tu teléfono. Volvé a la lista de agendados.',
  ),

  /// La agenda ya se cumplió o se canceló.
  agendaCerrada('agenda', 'Esa agenda ya se cumplió o se canceló. Revisá la lista de agendados.'),

  /// Se pidió cobrar en una ubicación alternativa una agenda que no es de cobranza (HU-VIS-006:
  /// «Solo aplica para tipo = COBRANZA»).
  alternativaSoloCobranza(
    'ubicacionAlternativa',
    'Solo una cobranza se puede agendar en otra ubicación. Elegí «Cobranza» o sacá la ubicación.',
  ),

  /// Se pidió una ubicación alternativa sin persona: la alternativa es de la persona (HU-UBI-013).
  alternativaSinPersona(
    'ubicacionAlternativa',
    'La ubicación alternativa es de una persona. Elegí a la persona o cobrá en la ubicación de la casa.',
  ),

  /// La alternativa se dio de baja (HU-VIS-006, escenario «alternativa dada de baja»: el texto es el
  /// de la HU, tal cual).
  alternativaInactiva(
    'ubicacionAlternativa',
    'La ubicación alternativa ya no está activa. Elegí otra o actualizá.',
  ),

  /// La alternativa no está en el teléfono (el pull no garantiza el orden): no se afirma que esté de
  /// baja.
  alternativaFaltante(
    'ubicacionAlternativa',
    'No encontramos esa ubicación alternativa en tu teléfono. Elegí otra o actualizá.',
  ),

  /// La persona ya no tiene esa ubicación como alternativa (se cambió o se quitó mientras se armaba la
  /// agenda).
  alternativaCambio(
    'ubicacionAlternativa',
    'La ubicación alternativa de esa persona cambió. Revisala y volvé a agendar.',
  );

  const MotivoRechazoAgenda(this.campo, this.mensaje);

  /// Campo del formulario al que se asocia el mensaje.
  final String campo;

  final String mensaje;
}
