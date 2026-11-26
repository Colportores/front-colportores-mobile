/// Dónde está el alta de una ubicación respecto del servidor (HU-UBI-006, «Par local»).
///
/// Lo que decide si la unión de un par puede encolar el trabajo «marcar como duplicado» (las dos están
/// en el servidor) o se hace en el teléfono sin encolar nada (contrato del motor, §6.2).
enum EstadoAltaUbicacion {
  /// El servidor ya la tiene: el alta subió, o la fila vino del servidor.
  enServidor,

  /// El alta no está en el servidor y no está viajando: `PENDING` (todavía no subió) o retenida por
  /// el motor (volvió en conflicto por dirección única, D1, o espera a otra que volvió). **Es
  /// «Par local»**: la unión se hace en el teléfono y no se encola.
  soloEnTelefono,

  /// El alta está viajando (`IN_FLIGHT`): no se adivina qué va a contestar el servidor. La unión
  /// espera la respuesta (si la aceptan se encola como cualquier otra; si vuelve en conflicto es
  /// «Par local»).
  subiendo,
}
