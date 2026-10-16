/// Sesión deslizante de 30 días (HU-AUTH-007, RA-SE04, §8.2.3).
///
/// Cada vez que el servidor emite o renueva la sesión (login o refresh del JWT, que solo pasa con
/// red), la ventana vuelve a arrancar. Si pasan [inactividadMaxima] sin actividad de red, la
/// sesión vence y hay que volver a entrar. Los datos locales no se tocan.
abstract final class PoliticaSesion {
  /// Cuánto aguanta la sesión sin actividad de red.
  static const inactividadMaxima = Duration(days: 30);

  /// Margen por el desfase entre el reloj del equipo y el del servidor (HU-AUTH-007: ±5 min).
  static const toleranciaReloj = Duration(minutes: 5);

  /// Hasta cuándo vale una sesión que el servidor emitió o renovó en [emitidaEn].
  static DateTime expiraEn(DateTime emitidaEn) => emitidaEn.toUtc().add(inactividadMaxima);

  /// `true` si una sesión que expira en [expiraEn] ya venció en [ahora], con la tolerancia de
  /// reloj a favor del usuario.
  static bool vencida(DateTime expiraEn, DateTime ahora) =>
      ahora.toUtc().isAfter(expiraEn.toUtc().add(toleranciaReloj));
}
