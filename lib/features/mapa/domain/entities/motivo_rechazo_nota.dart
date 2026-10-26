/// Por qué la persistencia rechazó una operación sobre las notas de una persona (HU-UBI-012).
///
/// Los decide la capa `data` dentro de la transacción (donde puede leer el estado real de la DB) y el
/// repositorio los traduce a un `FailureValidacion` con el [campo] y el [mensaje] de acá. Los mensajes
/// dicen qué pasa y qué hacer (a confirmar: el canvas 32E no dibuja estos casos).
enum MotivoRechazoNota {
  personaInexistente('persona', 'La persona ya no está en tu teléfono. Volvé atrás.'),
  soloLectura(
    'persona',
    'Esta persona está en solo lectura: podés ver sus notas, pero no agregar ni cambiar ninguna.',
  ),
  notaInexistente('nota', 'La nota ya no está en tu teléfono. Volvé a la lista de notas.'),
  notaBorrada('nota', 'La nota está borrada. Restaurala para poder editarla.');

  const MotivoRechazoNota(this.campo, this.mensaje);

  /// Campo al que se asocia el mensaje.
  final String campo;

  final String mensaje;
}
