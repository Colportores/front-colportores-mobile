import 'package:equatable/equatable.dart';

import 'cobranza.dart';

/// Una venta viva con lo que lleva cobrado y lo que todavía debe (R-CB01): el saldo es el monto de la
/// venta menos los cobros vivos. Todo en centavos.
///
/// Es una lectura del teléfono: nunca viaja al servidor ni lleva dato del cliente.
final class VentaConSaldo extends Equatable {
  const VentaConSaldo({
    required this.ventaId,
    required this.numeroTalonario,
    required this.fecha,
    required this.montoTotalCentavos,
    required this.cobradoCentavos,
    this.descripcion = '',
  });

  final String ventaId;

  /// El número impreso en el talonario («0042»).
  final String numeroTalonario;

  /// Cuándo se hizo la venta (UTC).
  final DateTime fecha;

  final int montoTotalCentavos;
  final int cobradoCentavos;

  /// Qué se vendió, en una línea («Colección de 1 libro», «Vida Feliz × 2»); vacío si no se sabe.
  final String descripcion;

  /// Lo que todavía debe: nunca negativo.
  int get saldoCentavos {
    final saldo = montoTotalCentavos - cobradoCentavos;
    return saldo > 0 ? saldo : 0;
  }

  bool get tieneSaldo => saldoCentavos > 0;

  @override
  List<Object?> get props => [
    ventaId,
    numeroTalonario,
    fecha,
    montoTotalCentavos,
    cobradoCentavos,
    descripcion,
  ];
}

/// Lo que dejó un cobro registrado: el cobro y cómo quedó la venta.
final class CobroRegistrado extends Equatable {
  const CobroRegistrado({required this.cobranza, required this.venta, this.yaEstaba = false});

  final Cobranza cobranza;

  /// La venta con el cobro ya descontado.
  final VentaConSaldo venta;

  /// El cobro ya estaba guardado (un doble toque o un reintento con el mismo id): no se escribió nada.
  final bool yaEstaba;

  /// El saldo llegó a cero: venta pagada (28·07).
  bool get ventaPagada => !venta.tieneSaldo;

  @override
  List<Object?> get props => [cobranza, venta, yaEstaba];
}
