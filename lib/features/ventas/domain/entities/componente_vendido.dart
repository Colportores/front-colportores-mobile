import 'package:equatable/equatable.dart';

/// Un producto y cuántas unidades del mismo trae **una** unidad de un combo vendido
/// (`venta_item.componentes`, backend 0071): lo fijo del combo y los libros que eligió la colportora.
final class ComponenteVendido extends Equatable {
  const ComponenteVendido({required this.productoId, this.cantidad = 1});

  final String productoId;
  final int cantidad;

  @override
  List<Object?> get props => [productoId, cantidad];
}
