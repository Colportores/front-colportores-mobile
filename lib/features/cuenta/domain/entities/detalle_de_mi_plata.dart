import 'package:equatable/equatable.dart';

/// Un cobro en efectivo que sigue en la mano, o una devolución de plata que lo bajó (HU-CTA-003,
/// vista 33C·01).
final class MovimientoEnMano extends Equatable {
  const MovimientoEnMano({
    required this.cliente,
    required this.fecha,
    required this.centavos,
    this.esDevolucion = false,
  });

  /// El nombre del cliente, tal como está en la lista de personas.
  final String cliente;

  /// Cuándo se cobró o se devolvió.
  final DateTime fecha;

  /// Lo cobrado (positivo) o lo devuelto al cliente en el momento (negativo): así la lista suma lo
  /// que dice la cifra.
  final int centavos;

  /// Es plata que se le devolvió al cliente al devolver un libro (decisión del 30/10 en #431).
  final bool esDevolucion;

  @override
  List<Object?> get props => [cliente, fecha, centavos, esDevolucion];
}

/// Un cliente con lo que debe, o al que se le debe (HU-CTA-003, vista 33C·02).
final class SaldoDeCliente extends Equatable {
  const SaldoDeCliente({required this.cliente, required this.desde, required this.centavos});

  final String cliente;

  /// Desde cuándo: la venta más vieja que todavía debe, o la primera devolución que dejó plata por
  /// devolverle.
  final DateTime desde;

  /// Siempre mayor que cero: el que no debe nada no aparece.
  final int centavos;

  @override
  List<Object?> get props => [cliente, desde, centavos];
}

/// El detalle de «Mi plata» del colportor (HU-CTA-003, vista 33C): qué clientes, en qué fecha y por
/// cuánto detrás de cada cifra de Mi Cuenta.
///
/// Todo en centavos y sacado del teléfono. En V1 son tres categorías: En mano, Por cobrar y, solo cuando
/// hay algo, Debo a clientes. «Depositado» espera que el teléfono sepa qué validó el coordinador.
final class DetalleDeMiPlata extends Equatable {
  const DetalleDeMiPlata({
    required this.enManoCentavos,
    required this.enMano,
    required this.porCobrarCentavos,
    required this.porCobrar,
    required this.deboCentavos,
    required this.deboAClientes,
  });

  /// El detalle de una cuenta sin movimientos.
  static const vacio = DetalleDeMiPlata(
    enManoCentavos: 0,
    enMano: [],
    porCobrarCentavos: 0,
    porCobrar: [],
    deboCentavos: 0,
    deboAClientes: [],
  );

  /// Lo mismo que «En mano» de Mi Cuenta: nunca negativo.
  final int enManoCentavos;
  final List<MovimientoEnMano> enMano;

  /// Lo mismo que «Por cobrar» de Mi Cuenta.
  final int porCobrarCentavos;
  final List<SaldoDeCliente> porCobrar;

  /// Lo que la colportora le debe a sus clientes por devoluciones («Se lo devuelvo después»).
  final int deboCentavos;
  final List<SaldoDeCliente> deboAClientes;

  /// «Debo a clientes» se muestra solo cuando hay algo (decisión de Cristian, 23/10, «Debo cliente»).
  bool get hayDeudaConClientes => deboCentavos > 0;

  @override
  List<Object?> get props => [
    enManoCentavos,
    enMano,
    porCobrarCentavos,
    porCobrar,
    deboCentavos,
    deboAClientes,
  ];
}
