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

/// Lo que falta entregar de una venta para **una** fecha (HU-VEN-003, vista 27C·02 «Entregas
/// pendientes» y la ficha de la persona, vista 32): sus filas pendientes, la fecha prevista y la cita de
/// esa fecha. Una venta puede tener una por cada grupo de libros diferido, cada una con su cita
/// (decisión de Cristian del 11/11, «Entrega cita»: lo que se suma a una venta abierta tiene su fecha).
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

  /// Las filas pendientes de la venta para esta fecha, en el orden en que se guardaron.
  final List<LineaPendiente> lineas;

  /// Cuándo se acordó entregar (UTC); `null` si todavía no tiene fecha («Poner fecha», 27C·02).
  final DateTime? fechaPrevista;

  /// La cita `ENTREGA` `PROGRAMADA` de estos libros, o `null` si no tiene (sin fecha, o la cita se
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

/// Cuál de las entregas pendientes de una venta se abre en «Marcar entregado» (27C·03): una venta
/// puede tener una por cada grupo de libros diferido (decisión de Cristian del 11/11, «Entrega cita»).
/// Se busca por la cita ([agendaId], que no cambia aunque la cita se mueva), si no por la fecha
/// prevista, y si no la que no tiene fecha ([sinFecha]). Sin nada de eso, la primera de la venta.
final class CualEntrega extends Equatable {
  const CualEntrega(this.ventaId, {this.agendaId, this.fechaPrevista, this.sinFecha = false});

  /// La de [entrega].
  factory CualEntrega.de(EntregaPendiente entrega) => CualEntrega(
    entrega.ventaId,
    agendaId: entrega.agendaId,
    fechaPrevista: entrega.fechaPrevista,
    sinFecha: entrega.sinFecha,
  );

  final String ventaId;
  final String? agendaId;
  final DateTime? fechaPrevista;
  final bool sinFecha;

  /// La que corresponde en [lista], o `null` si ya no está (se entregó, o se movió de fecha).
  EntregaPendiente? en(List<EntregaPendiente> lista) {
    final deLaVenta = [
      for (final e in lista)
        if (e.ventaId == ventaId) e,
    ];
    if (agendaId != null) {
      for (final e in deLaVenta) {
        if (e.agendaId == agendaId) return e;
      }
    }
    final fecha = fechaPrevista;
    if (fecha != null) {
      for (final e in deLaVenta) {
        if (e.fechaPrevista?.isAtSameMomentAs(fecha) ?? false) return e;
      }
      return null;
    }
    if (sinFecha) {
      for (final e in deLaVenta) {
        if (e.sinFecha) return e;
      }
      return null;
    }
    if (agendaId != null) return null;
    return deLaVenta.firstOrNull;
  }

  @override
  List<Object?> get props => [ventaId, agendaId, fechaPrevista?.millisecondsSinceEpoch, sinFecha];
}
