/// Cuánto debe cada persona (la línea «Saldo $ 1.200» del paso «¿Con quién?», vista 39 C·07). Local: el
/// saldo sale de las ventas y cobros del teléfono, nunca del servidor (ADR-004).
///
/// **Sin adaptador todavía**: las ventas y los cobros locales llegan con el S9, así que hasta entonces
/// el puerto lo cubre [SaldosDePersonasSinFuente] y la fila no muestra saldo.
abstract interface class SaldosDePersonas {
  /// El saldo pendiente, en centavos, de cada una de [personaIds] que debe algo. Una persona que no
  /// aparece en el mapa no tiene saldo conocido: no se muestra nada, ni «$ 0».
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds);
}

/// Mientras no haya ventas locales de dónde sacar el saldo: no se sabe de nadie.
final class SaldosDePersonasSinFuente implements SaldosDePersonas {
  const SaldosDePersonasSinFuente();

  @override
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds) async => const {};
}
