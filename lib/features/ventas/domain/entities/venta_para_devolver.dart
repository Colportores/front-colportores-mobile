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
/// - **ya pagó** = lo cobrado;
/// - **saldo** = lo que se queda − lo que ya pagó, sin bajar de cero: lo que se descuenta por una
///   devolución llega hasta el saldo y **nunca queda plata a favor del cliente** (decisión de Cristian,
///   03/11, «Devol. saldo»: no hay reembolso, ni «Lo retengo», ni «Debo al cliente»).
final class CuentaDeLaVenta extends Equatable {
  const CuentaDeLaVenta({
    required this.montoTotalCentavos,
    required this.cobradoCentavos,
    this.devueltoCentavos = 0,
  });

  /// Lo que costó la venta al hacerla; no cambia con las devoluciones.
  final int montoTotalCentavos;

  /// Lo que el cliente pagó en total (los cobros vivos).
  final int cobradoCentavos;

  /// Lo que valen las unidades que ya volvieron.
  final int devueltoCentavos;

  /// Lo que el cliente se queda comprando: nunca negativo.
  int get seQuedaConCentavos => math.max(0, montoTotalCentavos - devueltoCentavos);

  /// Lo que el cliente pagó.
  int get yaPagoCentavos => math.max(0, cobradoCentavos);

  /// Lo que todavía debe el cliente de lo que se queda.
  int get saldoCentavos => math.max(0, seQuedaConCentavos - yaPagoCentavos);

  /// Pagó todo lo que se queda comprando (también una venta de $ 0): una venta saldada no acepta
  /// devoluciones (decisión de Cristian, 03/11; el servidor la rechaza con `23514`).
  bool get estaSaldada => saldoCentavos == 0;

  @override
  List<Object?> get props => [montoTotalCentavos, cobradoCentavos, devueltoCentavos];
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
  );

  /// Lo que el cliente se queda comprando: nunca negativo.
  int get seQuedaConCentavos => cuenta.seQuedaConCentavos;

  /// Lo que el cliente pagó.
  int get yaPagoCentavos => cuenta.yaPagoCentavos;

  /// Lo que todavía debe el cliente de lo que se queda.
  int get saldoCentavos => cuenta.saldoCentavos;

  /// El cliente pagó todo lo que se queda comprando: la venta no acepta devoluciones.
  bool get estaSaldada => cuenta.estaSaldada;

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
    renglones,
  ];
}

/// Cómo queda la venta si se registra una devolución con lo elegido (31-02, 31-04, 31-05 y 31-06). Todo
/// en centavos; lo calcula `ReglasDeDevolucion.cuenta`.
final class CuentaDeLaDevolucion extends Equatable {
  const CuentaDeLaDevolucion({
    required this.unidades,
    required this.valorCentavos,
    required this.seQuedaConCentavos,
    required this.yaPagoCentavos,
    required this.sinDevolverCentavos,
    required this.saldoNuevoCentavos,
    required this.esTotal,
  });

  /// Cuántas unidades de renglón se devuelven.
  final int unidades;

  /// Lo que valen, en centavos.
  final int valorCentavos;

  /// Lo que el cliente se queda comprando después de esta devolución.
  final int seQuedaConCentavos;

  /// Lo que ya pagó.
  final int yaPagoCentavos;

  /// Lo que el cliente ya pagó y pasa de lo que se queda: no se le devuelve ni queda a su favor,
  /// porque lo descontado llega hasta el saldo y nunca queda plata a favor del cliente (decisión de
  /// Cristian, 03/11, «Devol. saldo»). 0 si lo devuelto cabe en el saldo.
  final int sinDevolverCentavos;

  /// Lo que le queda por pagar de lo que se queda.
  final int saldoNuevoCentavos;

  /// Con esta devolución vuelve todo lo que quedaba por devolver (31-07).
  final bool esTotal;

  /// Lo devuelto vale más que lo que el cliente debía: la venta queda saldada y la diferencia no se
  /// devuelve ni queda a su favor.
  bool get haySinDevolver => sinDevolverCentavos > 0;

  /// No se eligió nada.
  bool get estaVacia => unidades == 0;

  @override
  List<Object?> get props => [
    unidades,
    valorCentavos,
    seQuedaConCentavos,
    yaPagoCentavos,
    sinDevolverCentavos,
    saldoNuevoCentavos,
    esTotal,
  ];
}
