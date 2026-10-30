import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'componente_vendido.dart';

/// Un renglón de la venta en lo que la devolución necesita de él: qué es, cuánto se vendió, a qué
/// precio y cuánto de eso ya volvió. Un producto suelto ([productoId]) o un combo ([componentes] de
/// **una** unidad, por [cantidad] unidades).
///
/// Se devuelve por **unidades del renglón**: devolver el combo entero es devolver todos los libros de
/// ese renglón (decisión de Cristian, 27/10, «Devol. combo»). El saldo se calcula por renglón.
final class RenglonDeLaVenta extends Equatable {
  const RenglonDeLaVenta({
    required this.ventaItemId,
    required this.titulo,
    this.productoId,
    this.componentes,
    required this.cantidad,
    required this.precioUnitarioCentavos,
    this.unidadesDevueltas = 0,
  });

  /// `venta_item.id`.
  final String ventaItemId;

  /// Cómo se llama en la pantalla («Nuestros Hijos», «Colección Vida Feliz»).
  final String titulo;

  /// El producto vendido; `null` si el renglón es un combo.
  final String? productoId;

  /// Lo que traía una unidad del combo; `null` en un producto suelto.
  final List<ComponenteVendido>? componentes;

  /// Cuántas unidades se vendieron.
  final int cantidad;

  /// Lo que costaba cada una, en centavos (la foto al vender).
  final int precioUnitarioCentavos;

  /// Cuántas unidades del renglón ya volvieron en devoluciones anteriores.
  final int unidadesDevueltas;

  bool get esCombo => componentes != null;

  /// Cuántas unidades todavía se pueden devolver (nunca negativo).
  int get disponibles => math.max(0, cantidad - unidadesDevueltas);

  /// Lo que valen las unidades que ya volvieron, en centavos.
  int get valorDevueltoCentavos => math.min(cantidad, unidadesDevueltas) * precioUnitarioCentavos;

  @override
  List<Object?> get props => [
    ventaItemId,
    titulo,
    productoId,
    componentes,
    cantidad,
    precioUnitarioCentavos,
    unidadesDevueltas,
  ];
}

/// Las cuentas de una venta con sus devoluciones (ADR-002, HU-VEN-004): **la única fórmula** que usan
/// la pantalla de devolución, el saldo (HU-COB-005) y el color de la casa, para que nunca cuenten
/// cosas distintas. Todo en centavos.
///
/// - **se queda con** = total de la venta − lo que valen las unidades devueltas;
/// - **ya pagó** = lo cobrado − lo que ya se le reembolsó en el momento;
/// - **saldo** = lo que se queda − lo que ya pagó, sin bajar de cero;
/// - **debo al cliente** = lo que ya pagó − lo que se queda − lo que la colportora retuvo, sin bajar
///   de cero.
final class CuentaDeLaVenta extends Equatable {
  const CuentaDeLaVenta({
    required this.montoTotalCentavos,
    required this.cobradoCentavos,
    this.devueltoCentavos = 0,
    this.reembolsadoCentavos = 0,
    this.retenidoCentavos = 0,
  });

  /// Lo que costó la venta al hacerla; no cambia con las devoluciones.
  final int montoTotalCentavos;

  /// Lo que el cliente pagó en total (los cobros vivos).
  final int cobradoCentavos;

  /// Lo que valen las unidades que ya volvieron.
  final int devueltoCentavos;

  /// Lo que ya se le devolvió en el momento.
  final int reembolsadoCentavos;

  /// Lo que la colportora retuvo.
  final int retenidoCentavos;

  /// Lo que el cliente se queda comprando: nunca negativo.
  int get seQuedaConCentavos => math.max(0, montoTotalCentavos - devueltoCentavos);

  /// Lo que el cliente pagó y no se le devolvió.
  int get yaPagoCentavos => math.max(0, cobradoCentavos - reembolsadoCentavos);

  /// Lo que todavía debe el cliente de lo que se queda.
  int get saldoCentavos => math.max(0, seQuedaConCentavos - yaPagoCentavos);

  /// Lo que la colportora le debe al cliente (compromiso de reembolso futuro).
  int get deboAlClienteCentavos =>
      math.max(0, yaPagoCentavos - seQuedaConCentavos - retenidoCentavos);

  @override
  List<Object?> get props => [
    montoTotalCentavos,
    cobradoCentavos,
    devueltoCentavos,
    reembolsadoCentavos,
    retenidoCentavos,
  ];
}

/// Una venta tal como la ve la pantalla de devolución (vista 31): lo vendido, lo pagado y lo que ya
/// se devolvió. Todo en centavos. Es una lectura del teléfono: nunca viaja al servidor. Las cuentas son
/// las de [CuentaDeLaVenta].
final class VentaParaDevolver extends Equatable {
  const VentaParaDevolver({
    required this.ventaId,
    required this.numeroTalonario,
    required this.fecha,
    required this.montoTotalCentavos,
    required this.cobradoCentavos,
    this.reembolsadoCentavos = 0,
    this.retenidoCentavos = 0,
    required this.renglones,
  });

  final String ventaId;

  /// El número impreso en el talonario («0042»).
  final String numeroTalonario;

  /// Cuándo se hizo la venta (UTC): de acá corren las 72 h.
  final DateTime fecha;

  /// Lo que costó la venta al hacerla; no cambia con las devoluciones.
  final int montoTotalCentavos;

  /// Lo que el cliente pagó en total (los cobros vivos).
  final int cobradoCentavos;

  /// Lo que ya se le devolvió en el momento en devoluciones anteriores.
  final int reembolsadoCentavos;

  /// Lo que la colportora retuvo en devoluciones anteriores.
  final int retenidoCentavos;

  final List<RenglonDeLaVenta> renglones;

  /// Lo que valen las unidades que ya volvieron.
  int get devueltoCentavos => estaTodoDevuelto
      ? montoTotalCentavos
      : renglones.fold(0, (suma, r) => suma + r.valorDevueltoCentavos);

  /// Las cuentas de la venta tal como está hoy.
  CuentaDeLaVenta get cuenta => CuentaDeLaVenta(
    montoTotalCentavos: montoTotalCentavos,
    cobradoCentavos: cobradoCentavos,
    devueltoCentavos: devueltoCentavos,
    reembolsadoCentavos: reembolsadoCentavos,
    retenidoCentavos: retenidoCentavos,
  );

  /// Lo que el cliente se queda comprando: nunca negativo.
  int get seQuedaConCentavos => cuenta.seQuedaConCentavos;

  /// Lo que el cliente pagó y no se le devolvió.
  int get yaPagoCentavos => cuenta.yaPagoCentavos;

  /// Lo que todavía debe el cliente de lo que se queda.
  int get saldoCentavos => cuenta.saldoCentavos;

  /// Lo que la colportora le debe al cliente (compromiso de reembolso futuro).
  int get deboAlClienteCentavos => cuenta.deboAlClienteCentavos;

  /// Ya volvió todo lo vendido: no queda nada para devolver.
  bool get estaTodoDevuelto => renglones.isNotEmpty && renglones.every((r) => r.disponibles == 0);

  /// Cuántas unidades en total se pueden devolver todavía.
  int get unidadesDisponibles => renglones.fold(0, (suma, r) => suma + r.disponibles);

  @override
  List<Object?> get props => [
    ventaId,
    numeroTalonario,
    fecha,
    montoTotalCentavos,
    cobradoCentavos,
    reembolsadoCentavos,
    retenidoCentavos,
    renglones,
  ];
}

/// Cómo queda la venta si se registra una devolución con lo elegido (31-02, 31-06, 31-07). Todo en
/// centavos; lo calcula `ReglasDeDevolucion.cuenta`.
final class CuentaDeLaDevolucion extends Equatable {
  const CuentaDeLaDevolucion({
    required this.unidades,
    required this.valorCentavos,
    required this.seQuedaConCentavos,
    required this.yaPagoCentavos,
    required this.pagoDeMasCentavos,
    required this.saldoNuevoCentavos,
    required this.esTotal,
  });

  /// Cuántas unidades de renglón se devuelven.
  final int unidades;

  /// Lo que valen, en centavos.
  final int valorCentavos;

  /// Lo que el cliente se queda comprando después de esta devolución.
  final int seQuedaConCentavos;

  /// Lo que ya pagó y no se le devolvió.
  final int yaPagoCentavos;

  /// Lo que pagó de más y todavía no tiene destino: sobre esto la colportora elige.
  final int pagoDeMasCentavos;

  /// Lo que le queda por pagar de lo que se queda.
  final int saldoNuevoCentavos;

  /// Con esta devolución vuelve todo lo que quedaba por devolver (31-07).
  final bool esTotal;

  /// Hay plata de más: la elección de qué hacer con ella es obligatoria.
  bool get hayQueElegir => pagoDeMasCentavos > 0;

  /// No se eligió nada.
  bool get estaVacia => unidades == 0;

  @override
  List<Object?> get props => [
    unidades,
    valorCentavos,
    seQuedaConCentavos,
    yaPagoCentavos,
    pagoDeMasCentavos,
    saldoNuevoCentavos,
    esTotal,
  ];
}
