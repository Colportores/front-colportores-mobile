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

  /// Unidades entregadas y unidades vendidas en total: «1 de 2» (una venta de dos libros con uno
  /// entregado).
  final int entregasHechas;
  final int entregasTotales;

  /// Debe algo: la baja pide la doble confirmación (HU-UBI-011).
  bool get tieneSaldo => saldoCentavos > 0;

  /// Las unidades que todavía no se entregaron (nunca negativo).
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

/// De dónde sale la cuenta de cada persona (la ficha, 32B, y HU-UBI-011: advertir antes de dar de baja a
/// quien debe). Lo cubre el adaptador de la DB local (`CuentasDePersonasDrift`), con la misma regla de
/// saldo que `SaldosDePersonas`.
abstract interface class CuentasDePersonas {
  /// La cuenta de [personaId], o `null` si no tiene ventas (no hay nada que sumar: ni «$ 0» ni saldo).
  /// Si no se puede leer, lanza: quien la pide no da por hecho que no debe nada.
  Future<ResumenCuentaPersona?> resumenDe(String personaId);
}
