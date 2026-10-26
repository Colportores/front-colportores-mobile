import 'package:equatable/equatable.dart';

/// Lo que una persona compró, recibió y pagó (vista 32, KPI de la ficha y de la baja con saldo, y
/// `HU-VEN-005`). Todo en centavos de peso.
///
/// Local: sale de las ventas, las entregas y los cobros del teléfono, nunca del servidor (ADR-004). Se
/// muestra tal como lo informa quien lo calcula: **no se estima ni se completa**.
final class ResumenCuentaPersona extends Equatable {
  const ResumenCuentaPersona({
    required this.compradoCentavos,
    required this.pagadoCentavos,
    required this.saldoCentavos,
    required this.entregasHechas,
    required this.entregasTotales,
  });

  final int compradoCentavos;
  final int pagadoCentavos;

  /// Lo que todavía debe. Mayor que 0 = tiene saldo pendiente.
  final int saldoCentavos;

  /// Entregas hechas y entregas en total: «1 de 2».
  final int entregasHechas;
  final int entregasTotales;

  /// Debe algo: la baja pide la doble confirmación (HU-UBI-011).
  bool get tieneSaldo => saldoCentavos > 0;

  /// Las entregas que todavía no se hicieron (nunca negativo).
  int get entregasPendientes =>
      entregasTotales > entregasHechas ? entregasTotales - entregasHechas : 0;

  @override
  List<Object?> get props => [
    compradoCentavos,
    pagadoCentavos,
    saldoCentavos,
    entregasHechas,
    entregasTotales,
  ];
}

/// De dónde sale la cuenta de cada persona (HU-UBI-011: advertir antes de dar de baja a quien debe).
///
/// **Sin adaptador todavía**: las ventas y los cobros locales llegan con el S9, así que hasta entonces
/// el puerto lo cubre [CuentasDePersonasSinFuente] y nadie tiene saldo conocido. El S9 lo reemplaza
/// por el real, con la misma regla que `SaldosDePersonas`.
abstract interface class CuentasDePersonas {
  /// La cuenta de [personaId], o `null` si no tiene ventas (no se muestra nada, ni «$ 0»). Si no se
  /// puede leer, lanza: quien la pide no da por hecho que no debe nada.
  Future<ResumenCuentaPersona?> resumenDe(String personaId);
}

/// Mientras no haya ventas locales de dónde sacar la cuenta: no se sabe de nadie.
final class CuentasDePersonasSinFuente implements CuentasDePersonas {
  const CuentasDePersonasSinFuente();

  @override
  Future<ResumenCuentaPersona?> resumenDe(String personaId) async => null;
}
