import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../mapa/domain/entities/color_house_status.dart';

/// Lo que se entrega de una venta, de un producto (esquema-datos.md §Operaciones de campo, tabla
/// `entrega`): una fila por producto de la venta, no por renglón. Un combo se entrega como una fila
/// por componente, con la cantidad que trae (backend 0056).
///
/// [pendiente] dice si falta entregarlo (`true`, sin [fechaEntrega]) o ya se entregó (`false`, con la
/// fecha real). La entrega inmediata (HU-VEN-002) deja todo entregado.
class Entrega extends Equatable {
  Entrega({
    required this.id,
    required this.ventaId,
    required this.productoId,
    required this.cantidad,
    required this.pendiente,
    DateTime? fechaEntrega,
    required this.auditoria,
  }) : fechaEntrega = fechaEntrega == null ? null : instanteMs(fechaEntrega);

  final String id;

  /// FK a `venta.id`.
  final String ventaId;

  /// FK a `producto.id`.
  final String productoId;

  /// Cuántas unidades cuenta la fila; siempre 1 o más.
  final int cantidad;

  /// `true` = falta entregarlo.
  final bool pendiente;

  /// Cuándo se entregó de verdad (UTC); `null` mientras está [pendiente].
  final DateTime? fechaEntrega;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    ventaId,
    productoId,
    cantidad,
    pendiente,
    fechaEntrega,
    auditoria,
  ];
}

/// La entrega ya guardada, con cómo quedó la casa.
final class EntregaRegistrada extends Equatable {
  const EntregaRegistrada({required this.entregas, this.colorDeLaCasa, this.yaEstaba = false});

  /// Todas las filas vivas de la venta.
  final List<Entrega> entregas;

  /// El color de la casa después de entregar (`house_status`); `null` si la casa quedó sin color o
  /// no está en el teléfono.
  final ColorHouseStatus? colorDeLaCasa;

  /// La venta ya estaba toda entregada (un doble toque o un reintento): no se escribió nada de nuevo.
  final bool yaEstaba;

  /// Quedó algo por entregar.
  bool get quedaPendiente => entregas.any((e) => e.pendiente);

  @override
  List<Object?> get props => [entregas, colorDeLaCasa, yaEstaba];
}
