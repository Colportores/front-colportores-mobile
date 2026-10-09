/// Los espacios sin baja de una ubicación, tal como los ve la edición (HU-UBI-004, S17).
///
/// - [cantidad]: cuántos espacios activos tiene.
/// - [numeroDeptoUnico]: el `numero_depto` del único espacio activo, cuando [cantidad] es 1 y ese
///   tiene número; `null` en cualquier otro caso. Es lo que la línea «El departamento 3B queda como
///   el espacio de la casa, sin número.» le dice al colportor que va a perder.
typedef EspaciosActivos = ({int cantidad, String? numeroDeptoUnico});
