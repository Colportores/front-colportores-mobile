import 'package:equatable/equatable.dart';

import 'venta_para_devolver.dart';

/// Un renglón que la venta ya tiene (42B·09C, «YA VENDIDO · … · NO SE CAMBIA»): se muestra y no se
/// toca. Los nombres salen de la réplica del catálogo; vacíos si todavía no bajó.
final class RenglonYaVendido extends Equatable {
  const RenglonYaVendido({
    required this.nombre,
    required this.cantidad,
    required this.precioUnitarioCentavos,
    required this.subtotalCentavos,
    this.esCombo = false,
    this.librosDelCombo = 0,
    this.componentes = const [],
  });

  /// El nombre del producto o del combo.
  final String nombre;
  final int cantidad;
  final int precioUnitarioCentavos;
  final int subtotalCentavos;

  /// Es un combo (una colección vendida como un solo ítem).
  final bool esCombo;

  /// Cuántos libros traía **una** unidad del combo; 0 si no es un combo.
  final int librosDelCombo;

  /// Los nombres de lo que traía una unidad del combo, en orden; vacío si no es un combo.
  final List<String> componentes;

  @override
  List<Object?> get props => [
    nombre,
    cantidad,
    precioUnitarioCentavos,
    subtotalCentavos,
    esCombo,
    librosDelCombo,
    componentes,
  ];
}

/// Una venta **abierta** de una persona (HU-VEN-001, «Venta crece», decisión de Cristian del 10/11):
/// la que todavía tiene saldo o algo por entregar, a la que se le puede sumar otro libro sin otro
/// talonario. Una venta pagada y entregada, anulada o con todo devuelto está cerrada y no figura
/// (decisión de Cristian del 10/11, «Venta cerrada»; ver `ReglasDeVentaQueCrece.estaAbierta`).
///
/// Es una lectura del teléfono: nunca viaja al servidor. Lleva el motivo del monto a mano (texto de la
/// colportora): no sale en un `toString`.
final class VentaAbierta extends Equatable {
  const VentaAbierta({
    required this.ventaId,
    required this.espacioPersonaId,
    required this.numeroTalonario,
    required this.fecha,
    required this.montoTotalCentavos,
    required this.cobradoCentavos,
    this.devueltoCentavos = 0,
    this.entregada = false,
    this.entregadaEl,
    this.motivoMontoManual,
    this.renglones = const [],
    this.descripcion = '',
  });

  final String ventaId;

  /// El vínculo persona ↔ espacio al que se le vendió.
  final String espacioPersonaId;

  /// El número del talonario, que no cambia al sumar («Se suma a la venta 0039»).
  final String numeroTalonario;

  /// Cuándo se hizo la venta (UTC).
  final DateTime fecha;

  final int montoTotalCentavos;
  final int cobradoCentavos;

  /// Lo que valen los libros que ya volvieron (HU-VEN-004); 0 si no hubo.
  final int devueltoCentavos;

  /// Todo lo vendido (neto de devoluciones) ya está entregado.
  final bool entregada;

  /// El día de la última entrega, si está toda entregada; `null` si falta algo o no se sabe.
  final DateTime? entregadaEl;

  /// El motivo del total cambiado a mano, si lo tiene. Una venta lleva uno solo (`venta.motivo_monto_manual`).
  final String? motivoMontoManual;

  /// Lo que ya se vendió, renglón por renglón (42B·09C).
  final List<RenglonYaVendido> renglones;

  /// Qué se vendió, en una línea («Colección de 1 libro», «Vida Feliz × 2»), como en «¿Qué venta?».
  final String descripcion;

  CuentaDeLaVenta get cuenta => CuentaDeLaVenta(
    montoTotalCentavos: montoTotalCentavos,
    cobradoCentavos: cobradoCentavos,
    devueltoCentavos: devueltoCentavos,
  );

  /// Lo que todavía debe; nunca negativo.
  int get saldoCentavos => cuenta.saldoCentavos;

  /// Lo que ya pagó.
  int get pagadoCentavos => cuenta.yaPagoCentavos;

  bool get tieneSaldo => saldoCentavos > 0;

  /// La venta ya tiene un motivo del monto a mano.
  bool get tieneMotivo => (motivoMontoManual ?? '').trim().isNotEmpty;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    ventaId,
    espacioPersonaId,
    numeroTalonario,
    fecha,
    montoTotalCentavos,
    cobradoCentavos,
    devueltoCentavos,
    entregada,
    entregadaEl,
    motivoMontoManual,
    renglones,
    descripcion,
  ];
}
