/// De dónde sale cuándo es la cuota que toca de cada persona que debe (la línea «Debe $ 1.200 · cuota
/// sáb 26/10» de la hoja de la casa, vista 39 C·01 y C·02). Local: las cuotas de un plan son citas de
/// cobranza de la agenda del teléfono (HU-COB-004), nunca algo que se pida al servidor.
abstract interface class CuotasDePersonas {
  /// El día de la cuota que toca de cada una de [personaIds] que tiene un plan de cuotas: la más
  /// próxima, entre las cuotas todavía sin cubrir de todas sus ventas (si ya venció y sigue sin
  /// cubrir, es la vencida más vieja). Quien no tiene plan, o no tiene ninguna cuota abierta, no
  /// aparece en el mapa: su fila dice solo lo que debe. Un error de lectura sale por el `Future`.
  Future<Map<String, DateTime>> proximaCuotaDe(Iterable<String> personaIds);
}

/// Mientras no haya de dónde leer los planes de cuotas (la vista 30, HU-COB-004, todavía no está en
/// la rama de integración): no se sabe de nadie y la fila no dice cuota.
final class CuotasDePersonasSinFuente implements CuotasDePersonas {
  const CuotasDePersonasSinFuente();

  @override
  Future<Map<String, DateTime>> proximaCuotaDe(Iterable<String> personaIds) async => const {};
}

/// Avisa que lo que debe una persona (sus ventas, sus cobros, sus cuotas) pudo haber cambiado: la
/// hoja de la casa vuelve a leer sin que nadie recargue (HU-COB-005: «el saldo pasa a $ 700 sin
/// recargar pantalla»). El `Stream` que devuelve emite al suscribirse y cada vez que algo cambia; un
/// error o el cierre del `Stream` no frenan la hoja, que queda con lo último que leyó.
typedef CambiosDeLoQueSeDebe = Stream<void> Function();

/// Sin fuente de cambios (los tests): la hoja lee una sola vez y quien la abre la recarga.
Stream<void> sinCambiosDeLoQueSeDebe() => const Stream<void>.empty();
