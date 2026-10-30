/// Qué ubicaciones tienen una cobranza pendiente que viene de otra ubicación (HU-VIS-006: «el marker
/// de la alternativa muestra indicador "cobranza pendiente proveniente de otra ubicación"»).
///
/// Solo del teléfono (funciona sin conexión) y reactivo: se actualiza solo cuando se agenda, se
/// cancela o se cumple una cobranza, o cuando se une o se da de baja una ubicación.
abstract interface class CobranzasEnOtraUbicacionRepository {
  /// Los ids de las ubicaciones donde [colportorId] tiene al menos una agenda `COBRANZA` `PROGRAMADA`
  /// sin baja cuyo `ubicacion_alt_id` es esa ubicación y cuyo espacio es de **otra** ubicación. Un
  /// error al leer sale por el `Stream`.
  Stream<Set<String>> observarUbicaciones({required String colportorId});
}
