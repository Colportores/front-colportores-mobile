/// Pregunta si la sesión con la que arrancó un flujo largo sigue abierta.
///
/// Existe por la inicialización de la DB local (HU-AUTH-009): envolver la DEK con Argon2id tarda de
/// 1 a 2 s, y si el usuario cierra sesión en ese lapso, abrir la DB después la dejaría abierta
/// **sin sesión** — el cierre ya pasó y no hay nadie que la cierre (revisión del PR #44, #38).
///
/// Todo es **sincrónico** a propósito: el chequeo tiene que poder hacerse inmediatamente antes de
/// abrir, sin un `await` en el medio por donde se cuele el cierre.
abstract interface class VigenciaSesion {
  /// Toma nota de la sesión actual para compararla después. `null` si no hay sesión.
  TestigoSesion? tomarTestigo();
}

/// Constancia de la sesión que estaba abierta cuando se tomó.
abstract interface class TestigoSesion {
  /// `false` si desde que se tomó el testigo se pidió un cierre de sesión, o la sesión ya no es la
  /// misma.
  bool get sigueVigente;
}
