import '../entities/ficha_de_persona.dart';
import 'cuenta_de_persona.dart';

/// Por qué estado se filtra el historial de la ficha (vista 32B·03, «MOSTRAR»).
enum FiltroDeHistorial {
  /// Sin filtro: todo el historial.
  todo,

  /// Las ventas que todavía se deben.
  conSaldo,

  /// Las entregas que están por hacerse.
  entregaPendiente,
}

/// Aplica un [FiltroDeHistorial] a los movimientos de la ficha, sin cambiarles el orden.
abstract final class FiltroDeHistorialDeFicha {
  /// Las opciones que se ofrecen. «Con saldo» solo si se sabe cuánto debe la persona ([resumen] no es
  /// `null`): sin fuente de cobros no se afirma una deuda.
  static List<FiltroDeHistorial> disponibles(ResumenCuentaPersona? resumen) => [
    for (final f in FiltroDeHistorial.values)
      if (f != FiltroDeHistorial.conSaldo || resumen != null) f,
  ];

  /// Los movimientos de [historial] que quedan con [filtro].
  ///
  /// - [FiltroDeHistorial.todo]: todos.
  /// - [FiltroDeHistorial.conSaldo]: las ventas cuyo monto supera lo cobrado con su número de
  ///   talonario. Si [resumen] dice que la persona no debe nada, o no se sabe ([resumen] `null`),
  ///   ninguna: el filtro y la cuenta de arriba no se contradicen ni se afirma una deuda.
  /// - [FiltroDeHistorial.entregaPendiente]: las entregas pendientes.
  static List<MovimientoDeFicha> aplicar(
    List<MovimientoDeFicha> historial,
    FiltroDeHistorial filtro, {
    ResumenCuentaPersona? resumen,
  }) {
    switch (filtro) {
      case FiltroDeHistorial.todo:
        return historial;
      case FiltroDeHistorial.entregaPendiente:
        return [
          for (final m in historial)
            if (m is EntregaEnFicha && m.pendiente) m,
        ];
      case FiltroDeHistorial.conSaldo:
        if (resumen == null || !resumen.tieneSaldo) return const <MovimientoDeFicha>[];
        final cobrado = <String, int>{};
        for (final m in historial) {
          if (m is CobroEnFicha && m.numeroTalonario != null) {
            cobrado.update(
              m.numeroTalonario!,
              (v) => v + m.montoCentavos,
              ifAbsent: () => m.montoCentavos,
            );
          }
        }
        return [
          for (final m in historial)
            if (m is VentaEnFicha && m.montoCentavos > (cobrado[m.numeroTalonario] ?? 0)) m,
        ];
    }
  }
}
