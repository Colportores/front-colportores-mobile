import 'package:equatable/equatable.dart';

import 'linea_de_venta.dart';
import 'venta.dart';
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

/// Una venta ya guardada con sus ítems.
final class VentaGuardada extends Equatable {
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
