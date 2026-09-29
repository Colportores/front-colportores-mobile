/// Por qué la persistencia rechazó una operación sobre un espacio (HU-UBI-007).
///
/// Los decide la capa `data` dentro de la transacción (donde puede leer el estado real de la DB) y
/// el repositorio los traduce a un `FailureValidacion` con el [campo] y el [mensaje] de acá.
enum MotivoRechazoEspacio {
  ubicacionInexistente('ubicacionId', 'La ubicación no existe.'),
  ubicacionDeBaja(
    'ubicacionId',
    'La ubicación está dada de baja: restaurala antes de agregarle espacios.',
  ),
  ubicacionCasa('ubicacionId', 'Una casa tiene un único espacio y no se gestiona.'),
  deptoDuplicado('numeroDepto', 'Ya hay un espacio activo con ese número en esta ubicación.'),
  espacioInexistente('id', 'El espacio no existe.'),
  espacioDeBaja('id', 'El espacio está dado de baja: restauralo para modificarlo.');

  const MotivoRechazoEspacio(this.campo, this.mensaje);

  /// Campo del formulario al que se asocia el mensaje.
  final String campo;

  final String mensaje;
}
