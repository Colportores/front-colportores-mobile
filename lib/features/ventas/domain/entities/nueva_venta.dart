import 'package:equatable/equatable.dart';

import 'linea_de_venta.dart';
import 'venta.dart';
import 'venta_abierta.dart';
import 'venta_item.dart';

/// Todo lo que la colportora cargó en la pantalla de la venta (vista 27), para guardarlo.
final class NuevaVenta extends Equatable {
  const NuevaVenta({
    required this.ventaId,
    required this.colportorId,
    required this.espacioPersonaId,
    required this.numeroTalonario,
    required this.lineas,
    this.totalCobradoCentavos,
    this.motivoMontoManual = '',
    this.visitaId,
  });

  /// Se fija al abrir la pantalla: un reintento tras una falla, o un doble toque, escribe la misma
  /// venta y no otra.
  final String ventaId;
  final String colportorId;

  /// El vínculo persona ↔ espacio al que se le vendió.
  final String espacioPersonaId;

  /// Como lo escribió la colportora.
  final String numeroTalonario;
  final List<LineaDeVenta> lineas;

  /// El total que cobró si lo cambió a mano; `null` = el calculado.
  final int? totalCobradoCentavos;

  /// Por qué cambió el total (texto libre; lo lee el coordinador).
  final String motivoMontoManual;

  /// La visita de la entrevista que termina en esta venta, si viene de la casa en el mapa.
  final String? visitaId;

  /// Lleva el motivo del monto (texto libre): nunca debe salir en un log ni en un `toString`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    ventaId,
    colportorId,
    espacioPersonaId,
    numeroTalonario,
    lineas,
    totalCobradoCentavos,
    motivoMontoManual,
    visitaId,
  ];
}

/// Lo que se le suma a una venta abierta (HU-VEN-001, «Venta crece», 42B·09C): los renglones nuevos,
/// con el precio de la ciudad de la casa de hoy, y el monto a mano de **lo que se suma**, si lo cambió.
final class SumaALaVenta extends Equatable {
  const SumaALaVenta({
    required this.sumaId,
    required this.colportorId,
    required this.venta,
    required this.lineas,
    this.sumadoACobrarCentavos,
    this.motivoMontoManual = '',
  });

  /// Se fija al abrir la pantalla: es el id del primer renglón nuevo, así que un reintento tras una
  /// falla, o un doble toque, no suma dos veces.
  final String sumaId;
  final String colportorId;

  /// La venta abierta a la que se suma, como se leyó al abrir.
  final VentaAbierta venta;
  final List<LineaDeVenta> lineas;

  /// Lo que cobra por lo que suma, si lo cambió a mano; `null` = el calculado.
  final int? sumadoACobrarCentavos;

  /// Por qué cambió el monto de lo que suma (texto libre; lo lee el coordinador).
  final String motivoMontoManual;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    sumaId,
    colportorId,
    venta,
    lineas,
    sumadoACobrarCentavos,
    motivoMontoManual,
  ];
}

/// Una venta ya guardada con sus ítems.
class VentaGuardada extends Equatable {
  const VentaGuardada({required this.venta, required this.items, this.yaEstaba = false});

  final Venta venta;
  final List<VentaItem> items;

  /// La venta ya estaba (un doble toque o un reintento): no se escribió nada de nuevo.
  final bool yaEstaba;

  /// Lo que la colportora cobró por la venta, en centavos.
  int get totalCentavos => venta.montoTotalCentavos;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [venta, items, yaEstaba];
}

/// Una venta abierta a la que se le sumaron renglones (42B·09C → 09D). [venta] es la venta con el
/// total nuevo y [items] son **solo los renglones que se sumaron**: la entrega del libro nuevo
/// (09D) trabaja con ellos y no toca lo pendiente de antes.
final class VentaQueCrecio extends VentaGuardada {
  const VentaQueCrecio({
    required super.venta,
    required super.items,
    required this.totalAnteriorCentavos,
    required this.sumadoEl,
    super.yaEstaba,
  });

  /// El total que tenía la venta antes de sumar.
  final int totalAnteriorCentavos;

  /// Cuándo se sumó (UTC): lo que se registre de la entrega desde acá es de lo sumado.
  final DateTime sumadoEl;

  /// Cuánto sumó al total.
  int get sumadoCentavos => venta.montoTotalCentavos - totalAnteriorCentavos;

  /// Cuántas unidades se sumaron («Libro sumado» o «Libros sumados»).
  int get unidades => items.fold(0, (suma, item) => suma + item.cantidad);

  @override
  List<Object?> get props => [...super.props, totalAnteriorCentavos, sumadoEl];
}
