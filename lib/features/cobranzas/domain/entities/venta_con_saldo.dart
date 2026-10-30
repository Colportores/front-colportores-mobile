import 'package:equatable/equatable.dart';

import '../../../ventas/domain/entities/venta_para_devolver.dart';
import 'cobranza.dart';

/// Una venta viva con lo que lleva cobrado y lo que todavía debe (R-CB01): el saldo es lo que el
/// cliente se queda comprando —el monto de la venta menos lo devuelto (HU-VEN-004)— menos lo que ya
/// pagó (los cobros vivos menos lo que se le reembolsó). Sin devoluciones es el monto menos los cobros.
/// Todo en centavos; la cuenta es la de [CuentaDeLaVenta], la misma de la pantalla de devolución.
///
/// Es una lectura del teléfono: nunca viaja al servidor ni lleva dato del cliente.
final class VentaConSaldo extends Equatable {
  const VentaConSaldo({
    required this.ventaId,
    required this.numeroTalonario,
    required this.fecha,
    required this.montoTotalCentavos,
    required this.cobradoCentavos,
    this.devueltoCentavos = 0,
    this.reembolsadoCentavos = 0,
    this.retenidoCentavos = 0,
    this.descripcion = '',
  });

  final String ventaId;

  /// El número impreso en el talonario («0042»).
  final String numeroTalonario;

  /// Cuándo se hizo la venta (UTC).
  final DateTime fecha;

  final int montoTotalCentavos;
  final int cobradoCentavos;

  /// Lo que valen los libros que ya volvieron en devoluciones (HU-VEN-004); 0 si no hubo.
  final int devueltoCentavos;

  /// Lo que ya se le devolvió al cliente en el momento al devolver; 0 si no hubo.
  final int reembolsadoCentavos;

  /// Lo que la colportora retuvo al devolver; 0 si no hubo.
  final int retenidoCentavos;

  /// Qué se vendió, en una línea («Colección de 1 libro», «Vida Feliz × 2»); vacío si no se sabe.
  final String descripcion;

  /// Las cuentas de la venta con sus devoluciones.
  CuentaDeLaVenta get cuenta => CuentaDeLaVenta(
    montoTotalCentavos: montoTotalCentavos,
    cobradoCentavos: cobradoCentavos,
    devueltoCentavos: devueltoCentavos,
    reembolsadoCentavos: reembolsadoCentavos,
    retenidoCentavos: retenidoCentavos,
  );

  /// Lo que el cliente se queda comprando: el monto menos lo devuelto.
  int get seQuedaConCentavos => cuenta.seQuedaConCentavos;

  /// Lo que el cliente pagó y no se le devolvió.
  int get yaPagoCentavos => cuenta.yaPagoCentavos;

  /// Lo que todavía debe: nunca negativo.
  int get saldoCentavos => cuenta.saldoCentavos;

  /// Lo que la colportora le debe al cliente por lo que pagó de más («Debo al cliente»); 0 si nada.
  int get deboAlClienteCentavos => cuenta.deboAlClienteCentavos;

  bool get tieneSaldo => saldoCentavos > 0;

  @override
  List<Object?> get props => [
    ventaId,
    numeroTalonario,
    fecha,
    montoTotalCentavos,
    cobradoCentavos,
    devueltoCentavos,
    reembolsadoCentavos,
    retenidoCentavos,
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
