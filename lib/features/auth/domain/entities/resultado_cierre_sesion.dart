/// Cómo terminó un cierre de sesión que salió bien en este teléfono (HU-AUTH-006).
///
/// En los dos casos la sesión local ya no existe y la DEK en claro se fue de memoria; lo que cambia
/// es si el servidor ya se enteró.
enum ResultadoCierreSesion {
  /// El JWT se revocó en Supabase Auth.
  completo,

  /// Sin conexión: la revocación del JWT quedó pendiente y se reintenta sola (HU-AUTH-006,
  /// escenario "Logout sin conexión").
  revocacionPendiente,
}
