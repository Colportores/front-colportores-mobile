import 'package:equatable/equatable.dart';

import '../../../depositos/domain/entities/totales_de_depositos.dart';

/// Un cobro en efectivo que sigue en la mano, o un depósito que lo sacó (HU-CTA-003, vista 33C·01).
final class MovimientoEnMano extends Equatable {
  const MovimientoEnMano({
    required this.cliente,
    required this.fecha,
    required this.centavos,
    this.deposito,
  });

  /// El nombre del cliente, tal como está en la lista de personas; vacío en un depósito.
  final String cliente;

  /// Cuándo se cobró o se depositó.
  final DateTime fecha;

  /// Lo cobrado (positivo) o lo depositado (negativo): así la lista suma lo que dice la cifra.
  final int centavos;

  /// El depósito que sacó plata de la mano; `null` en un cobro.
  final DepositoDeLaLista? deposito;

  bool get esDeposito => deposito != null;

  @override
  List<Object?> get props => [cliente, fecha, centavos, deposito];
}

/// Un cliente con lo que debe (HU-CTA-003, vista 33C·02).
final class SaldoDeCliente extends Equatable {
  const SaldoDeCliente({required this.cliente, required this.desde, required this.centavos});

  final String cliente;

  /// Desde cuándo: la venta más vieja que todavía debe.
  final DateTime desde;

  /// Siempre mayor que cero: el que no debe nada no aparece.
  final int centavos;

  @override
  List<Object?> get props => [cliente, desde, centavos];
}

/// Lo depositado según lo que dijo el coordinador (HU-CTA-003, vista 33C): los depósitos validados,
/// que son los que suman a «Depositado», y aparte los que esperan su validación (decisión «Acredita
/// V1», 23/10). Un depósito rechazado no está en ninguna lista.
final class DepositadoEnMiPlata extends Equatable {
  const DepositadoEnMiPlata({required this.validados, required this.porValidar});

  /// Los depósitos que el coordinador validó, el más viejo primero.
  final List<DepositoDeLaLista> validados;

  /// Los depósitos que todavía esperan su validación, el más viejo primero.
  final List<DepositoDeLaLista> porValidar;

  /// Lo mismo que «Depositado» de Mi Cuenta.
  int get validadoCentavos => _suma(validados);

  /// Lo que suma a «Depositado» cuando el coordinador valide.
  int get porValidarCentavos => _suma(porValidar);

  static int _suma(List<DepositoDeLaLista> depositos) =>
      depositos.fold<int>(0, (suma, d) => suma + d.montoCentavos);

  @override
  List<Object?> get props => [validados, porValidar];
}

/// El detalle de «Mi plata» del colportor (HU-CTA-003, vista 33C): qué depósitos, qué clientes, en qué
/// fecha y por cuánto detrás de cada cifra de Mi Cuenta.
///
/// Todo en centavos y sacado del teléfono. En V1 son tres categorías: Depositado, En mano y Por cobrar.
final class DetalleDeMiPlata extends Equatable {
  const DetalleDeMiPlata({
    this.depositado,
    required this.enManoCentavos,
    required this.enMano,
    required this.porCobrarCentavos,
    required this.porCobrar,
  });

  /// El detalle de una cuenta sin movimientos que todavía no bajó nada del servidor.
  static const vacio = DetalleDeMiPlata(
    enManoCentavos: 0,
    enMano: [],
    porCobrarCentavos: 0,
    porCobrar: [],
  );

  /// Lo depositado; `null` mientras el teléfono no bajó nada del servidor: ahí «Depositado» no se
  /// dibuja, ni un cero inventado (igual que en Mi Cuenta).
  final DepositadoEnMiPlata? depositado;

  /// Lo mismo que «En mano» de Mi Cuenta: los cobros en efectivo menos lo depositado, nunca negativo.
  final int enManoCentavos;
  final List<MovimientoEnMano> enMano;

  /// Lo mismo que «Por cobrar» de Mi Cuenta.
  final int porCobrarCentavos;
  final List<SaldoDeCliente> porCobrar;

  @override
  List<Object?> get props => [depositado, enManoCentavos, enMano, porCobrarCentavos, porCobrar];
}
