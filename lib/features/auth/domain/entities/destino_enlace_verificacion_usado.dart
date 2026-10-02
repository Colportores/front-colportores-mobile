/// Qué le pasó a un enlace de verificación de email que Supabase rechazó con `otp_expired`
/// (HU-AUTH-002, «"Vencido" vs "ya usado"»).
///
/// Supabase manda el mismo error para un enlace vencido y para uno que ya se usó, así que la app lo
/// deduce con lo que sabe: si hay sesión, o si el login en silencio entra, el email ya estaba
/// verificado.
enum DestinoEnlaceVerificacionUsado {
  /// «Tu email ya está verificado»: hay sesión activa o el login en silencio entró.
  yaVerificado,

  /// «El enlace expiró»: el login en silencio respondió `email_not_confirmed`, así que la cuenta
  /// sigue sin confirmar y lo que corresponde es **Reenviar**.
  expirado,

  /// «Este enlace ya no sirve…»: no hay sesión ni forma de probar con el login (o el login falló
  /// por otra cosa: red, credenciales). Ofrece **Ir al login** y **Reenviar**.
  noSabemos,
}
