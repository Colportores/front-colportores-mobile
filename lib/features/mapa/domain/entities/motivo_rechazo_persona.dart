/// Por qué la persistencia rechazó dar de alta una persona en un espacio (HU-UBI-008).
///
/// Los decide la capa `data` dentro de la transacción (donde puede leer el estado real de la DB) y el
/// repositorio los traduce a un `FailureValidacion` con el [campo] y el [mensaje] de acá. Los
/// mensajes dicen qué pasa y qué hacer; «Espacio dado de baja» es el rótulo de la HU.
enum MotivoRechazoPersona {
  espacioInexistente('espacio', 'El espacio ya no existe en tu teléfono. Volvé a la lista.'),
  espacioDeBaja('espacio', 'Espacio dado de baja: solo lectura. Restauralo para agregar clientes.'),
  ubicacionDeBaja(
    'espacio',
    'La ubicación está dada de baja: reactivala para agregar clientes a sus espacios.',
  );

  const MotivoRechazoPersona(this.campo, this.mensaje);

  /// Campo del formulario al que se asocia el mensaje.
  final String campo;

  final String mensaje;
}
