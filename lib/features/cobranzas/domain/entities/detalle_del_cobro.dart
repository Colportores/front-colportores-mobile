import 'package:equatable/equatable.dart';

import 'cobranza.dart';
import 'venta_con_saldo.dart';

/// Un cobro con la venta que paga y a quién se le cobró (vista 30 B, «Detalle del cobro», HU-COB-006).
///
/// Es una lectura del teléfono: lleva el nombre del cliente, así que **no** se imprime ni va a los logs
/// (`stringify` apagado), y nunca viaja al servidor (ADR-004, R-CB03).
final class DetalleDelCobro extends Equatable {
  const DetalleDelCobro({required this.cobranza, required this.venta, this.cliente});

  final Cobranza cobranza;

  /// La venta, con el saldo de ahora: si el cobro está anulado, ya no lo cuenta (30B-05).
  final VentaConSaldo venta;

  /// «María Fernández», o `null` si la venta quedó sin persona o no se pudo leer.
  final String? cliente;

  /// Lo que dura la ventana para anular, desde el cobro (S40; decisión de Cristian, 23/10, «Anular 72 h»).
  static const ventana = Duration(hours: 72);

  /// Hasta cuándo se puede anular (UTC), inclusive: 72 h después de la fecha del cobro, que es desde donde
  /// el servidor cuenta.
  DateTime get puedeAnularseHasta => cobranza.fecha.add(ventana);

  /// Si en [ahora] todavía se puede anular por el plazo (no mira si ya está anulado ni el ticket).
  bool dentroDelPlazo(DateTime ahora) => !ahora.toUtc().isAfter(puedeAnularseHasta);

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [cobranza, venta, cliente];
}

/// Lo que dejó anular un cobro: cómo quedó y si ya estaba anulado (un doble toque o un reintento: no se
/// escribió nada).
final class AnulacionHecha extends Equatable {
  const AnulacionHecha({required this.detalle, this.yaEstaba = false});

  final DetalleDelCobro detalle;
  final bool yaEstaba;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [detalle, yaEstaba];
}
