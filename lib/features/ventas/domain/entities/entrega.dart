import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../mapa/domain/entities/color_house_status.dart';

/// Lo que se entrega de una venta, de un producto (esquema-datos.md §Operaciones de campo, tabla
/// `entrega`): una fila por producto de la venta, no por ítem. Un combo se entrega como una fila por
/// componente, con la cantidad que trae (backend 0056).
///
/// [pendiente] dice si falta entregarlo (`true`, sin [fechaEntrega]) o ya se entregó (`false`, con la
/// fecha real). La entrega inmediata (HU-VEN-002) deja entregado lo que la colportora marcó y
/// pendiente lo que destildó; la entrega diferida (HU-VEN-003) le pone a lo pendiente la
/// [fechaPrevista] en que se acordó entregar.
class Entrega extends Equatable {
  Entrega({
    required this.id,
    required this.ventaId,
    required this.productoId,
    required this.cantidad,
    required this.pendiente,
    DateTime? fechaPrevista,
    DateTime? fechaEntrega,
    required this.auditoria,
  }) : fechaPrevista = fechaPrevista == null ? null : instanteMs(fechaPrevista),
       fechaEntrega = fechaEntrega == null ? null : instanteMs(fechaEntrega);

  final String id;

  /// FK a `venta.id`.
  final String ventaId;

  /// FK a `producto.id`.
  final String productoId;

  /// Cuántas unidades cuenta la fila; siempre 1 o más.
  final int cantidad;

  /// `true` = falta entregarlo.
  final bool pendiente;

  /// Cuándo se acordó entregar (UTC); `null` si no hay fecha acordada (una entrega inmediata no la
  /// tiene y una pendiente puede quedar sin ella). Sigue ahí cuando la fila ya se entregó: es lo que
  /// se acordó, y [fechaEntrega] lo que pasó.
  final DateTime? fechaPrevista;

  /// Cuándo se entregó de verdad (UTC); `null` mientras está [pendiente].
  final DateTime? fechaEntrega;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  /// Esta misma fila con otros valores de sus fechas y su estado, y el instante de la edición.
  /// [sinFechaPrevista] la deja sin fecha acordada.
  Entrega editada({
    required DateTime ahora,
    bool? pendiente,
    DateTime? fechaPrevista,
    bool sinFechaPrevista = false,
    DateTime? fechaEntrega,
  }) => Entrega(
    id: id,
    ventaId: ventaId,
    productoId: productoId,
    cantidad: cantidad,
    pendiente: pendiente ?? this.pendiente,
    fechaPrevista: sinFechaPrevista ? null : (fechaPrevista ?? this.fechaPrevista),
    fechaEntrega: fechaEntrega ?? this.fechaEntrega,
    auditoria: Auditoria(
      createdAt: auditoria.createdAt,
      updatedAt: ahora,
      createdBy: auditoria.createdBy,
      deletedAt: auditoria.deletedAt,
      syncVersion: auditoria.syncVersion,
    ),
  );

  @override
  List<Object?> get props => [
    id,
    ventaId,
    productoId,
    cantidad,
    pendiente,
    fechaPrevista,
    fechaEntrega,
    auditoria,
  ];
}

/// La entrega ya guardada, con cómo quedó la casa.
final class EntregaRegistrada extends Equatable {
  const EntregaRegistrada({required this.entregas, this.colorDeLaCasa, this.yaEstaba = false});

  /// Todas las filas de la venta, las entregadas y las que siguen pendientes.
  final List<Entrega> entregas;

  /// El color de la casa después de entregar (`house_status`); `null` si la casa quedó sin color o
  /// no está en el teléfono.
  final ColorHouseStatus? colorDeLaCasa;

  /// La venta ya tenía su entrega (un doble toque o un reintento): no se escribió nada de nuevo.
  final bool yaEstaba;

  /// Quedó algo por entregar.
  bool get quedaPendiente => entregas.any((e) => e.pendiente);

  @override
  List<Object?> get props => [entregas, colorDeLaCasa, yaEstaba];
}
