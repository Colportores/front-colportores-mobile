import 'package:equatable/equatable.dart';

/// Un cobro en efectivo que sigue en la mano (HU-CTA-003, vista 33C·01).
final class MovimientoEnMano extends Equatable {
  const MovimientoEnMano({required this.cliente, required this.fecha, required this.centavos});

  /// El nombre del cliente, tal como está en la lista de personas.
  final String cliente;

  /// Cuándo se cobró o se devolvió.
  final DateTime fecha;

  /// Lo cobrado: la lista suma lo que dice la cifra.
  final int centavos;

  @override
  List<Object?> get props => [cliente, fecha, centavos];
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

/// El detalle de «Mi plata» del colportor (HU-CTA-003, vista 33C): qué clientes, en qué fecha y por
/// cuánto detrás de cada cifra de Mi Cuenta.
///
/// Todo en centavos y sacado del teléfono. En V1 son dos categorías: En mano y Por cobrar. «Depositado»
/// espera la decisión de qué lleva su detalle.
final class DetalleDeMiPlata extends Equatable {
  const DetalleDeMiPlata({
    required this.enManoCentavos,
    required this.enMano,
    required this.porCobrarCentavos,
    required this.porCobrar,
  });

  /// El detalle de una cuenta sin movimientos.
  static const vacio = DetalleDeMiPlata(
    enManoCentavos: 0,
    enMano: [],
    porCobrarCentavos: 0,
    porCobrar: [],
  );

  /// Lo mismo que «En mano» de Mi Cuenta: nunca negativo.
  final int enManoCentavos;
  final List<MovimientoEnMano> enMano;

  /// Lo mismo que «Por cobrar» de Mi Cuenta.
  final int porCobrarCentavos;
  final List<SaldoDeCliente> porCobrar;

  @override
  List<Object?> get props => [enManoCentavos, enMano, porCobrarCentavos, porCobrar];
}
