/// Los correos a los que el servidor rechazó el reenvío del email de verificación por límite de
/// intentos, y hasta cuándo el reenvío a esa dirección queda bloqueado con el candado (HU-AUTH-002,
/// vista 12-A06; decisión de Cristian, 30/09, front-colportores-mobile#221 y #239; seguimiento
/// #249).
///
/// El candado es **por dirección de correo** (otra dirección no queda bloqueada) y se guarda fuera
/// de la sesión, así que **sobrevive a reiniciar la app**. Los correos van normalizados (sin
/// espacios alrededor y en minúsculas, como los guarda Supabase): el que normaliza es el caso de
/// uso, no el repositorio.
///
/// Nunca lanza: si el almacén falla, [leer] devuelve vacío y [guardar] queda en el log (el límite
/// de verdad lo aplica el servidor, que vuelve a rechazar). Las operaciones se ejecutan **en el
/// orden en que se piden**.
abstract interface class BloqueoReenvioVerificacionRepository {
  /// Los bloqueos guardados: correo normalizado → instante (UTC) en que vence. Puede traer alguno
  /// ya vencido: el que consulta decide qué hacer con él.
  Future<Map<String, DateTime>> leer();

  /// Guarda que el reenvío a [correo] queda bloqueado hasta [vence], reemplazando el anterior de esa
  /// dirección, y descarta de lo guardado los bloqueos que ya vencieron a [ahora].
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora});
}
