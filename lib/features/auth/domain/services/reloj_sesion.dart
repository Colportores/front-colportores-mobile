/// Reloj con el que se mide la ventana de 30 días de la sesión (HU-AUTH-007).
///
/// No puede volver atrás: devuelve el instante actual del equipo o el más alto que ya vio, el
/// mayor de los dos. Así atrasar el reloj del teléfono no estira una sesión sin red.
abstract interface class RelojSesion {
  /// El instante actual, nunca anterior al más alto ya visto. Lo registra si avanzó.
  Future<DateTime> ahora();

  /// Registra un instante visto por otro camino, como el `iat` de un JWT (reloj del servidor).
  Future<void> registrar(DateTime visto);
}
