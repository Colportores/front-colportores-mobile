import 'package:equatable/equatable.dart';

/// Una fila de lo que falta entregar de una venta: un producto con su cantidad.
final class LineaPendiente extends Equatable {
  const LineaPendiente({required this.entregaId, required this.productoId, required this.cantidad});

  /// `entrega.id` de la fila pendiente.
  final String entregaId;

  final String productoId;

  /// Cuántas unidades faltan; siempre 1 o más.
  final int cantidad;

  @override
  List<Object?> get props => [entregaId, productoId, cantidad];
}

/// Lo que falta entregar de una venta (HU-VEN-003, vista 27C·02 «Entregas pendientes» y la ficha de
/// la persona, vista 32): sus filas pendientes, la fecha prevista y la cita de esa fecha.
///
/// **Sin dato de la persona** (R-UB09): lleva solo ids. Quien dibuja la lista resuelve el nombre y la
/// dirección por [espacioPersonaId], en el teléfono.
final class EntregaPendiente extends Equatable {
  const EntregaPendiente({
    required this.ventaId,
    required this.espacioPersonaId,
    required this.lineas,
    this.fechaPrevista,
    this.agendaId,
    this.espacioId,
    this.numeroTalonario,
  });

  final String ventaId;

  /// El vínculo persona ↔ espacio de la venta.
  final String espacioPersonaId;

  /// Las filas pendientes de la venta, en el orden en que se guardaron.
  final List<LineaPendiente> lineas;

  /// Cuándo se acordó entregar (UTC); `null` si todavía no tiene fecha («Poner fecha», 27C·02).
  final DateTime? fechaPrevista;

  /// La cita `ENTREGA` `PROGRAMADA` de esta venta, o `null` si no tiene (sin fecha, o la cita se
  /// canceló a mano).
  final String? agendaId;

  /// La casa o el depto de la venta (`espacio.id`), con que la lista resuelve la dirección y el
  /// nombre en el teléfono; `null` si el vínculo ya no está.
  final String? espacioId;

  /// El talonario de la venta («0042»), para el encabezado «VENTA 0042».
  final String? numeroTalonario;

  /// No tiene fecha prevista.
  bool get sinFecha => fechaPrevista == null;

  /// La fecha prevista cae en un día anterior a hoy (27C·02 «Atrasadas»), en hora local. Sin fecha no
  /// está atrasada: no se sabe para cuándo era.
  bool estaAtrasada(DateTime ahora) {
    final fecha = fechaPrevista;
    if (fecha == null) return false;
    final dia = fecha.toLocal();
    final hoy = ahora.toLocal();
    return DateTime(dia.year, dia.month, dia.day).isBefore(DateTime(hoy.year, hoy.month, hoy.day));
  }

  @override
  List<Object?> get props => [
    ventaId,
    espacioPersonaId,
    lineas,
    fechaPrevista,
    agendaId,
    espacioId,
    numeroTalonario,
  ];
}
