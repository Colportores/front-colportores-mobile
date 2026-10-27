import 'package:equatable/equatable.dart';

import 'componente_vendido.dart';

/// Lo que se agregó a una venta antes de guardarla: un producto suelto o un combo, con su cantidad y
/// el precio que regía en la ciudad de la casa. Cada línea termina en un `venta_item`.
sealed class LineaDeVenta extends Equatable {
  const LineaDeVenta({required this.cantidad, required this.precioCentavos});

  /// Cuántas unidades; siempre 1 o más.
  final int cantidad;

  /// El precio vigente de **una** unidad en la ciudad de la casa, en centavos (nunca `double`).
  final int precioCentavos;

  /// Lo que la línea suma al total de la venta, en centavos.
  int get subtotalCentavos => cantidad * precioCentavos;

  /// El precio unitario que queda anotado en el `venta_item`.
  int get precioUnitarioGuardado => precioCentavos;
}

/// Un producto suelto (libro, revista o ejemplar misionero).
final class LineaDeProducto extends LineaDeVenta {
  const LineaDeProducto({
    required this.productoId,
    required super.cantidad,
    required super.precioCentavos,
    this.sinCobrar = false,
  });

  final String productoId;

  /// «Entregarlos sin cobrar» (27A·08): un ejemplar misionero que se regala. No suma al total y el
  /// ítem queda con precio 0, porque lo que se cobró por él es nada (`subtotal = cantidad × precio`).
  final bool sinCobrar;

  @override
  int get subtotalCentavos => sinCobrar ? 0 : super.subtotalCentavos;

  @override
  int get precioUnitarioGuardado => sinCobrar ? 0 : precioCentavos;

  @override
  List<Object?> get props => [productoId, cantidad, precioCentavos, sinCobrar];
}

/// Un combo vendido como **un solo ítem** con el precio del combo (C10).
final class LineaDeCombo extends LineaDeVenta {
  const LineaDeCombo({
    required this.comboId,
    required super.cantidad,
    required super.precioCentavos,
    required this.componentes,
  });

  final String comboId;

  /// Lo que trae **una** unidad: lo fijo del combo más los libros que eligió. Las unidades con
  /// elecciones distintas son líneas separadas de cantidad 1 (convención de backend-supabase#138).
  final List<ComponenteVendido> componentes;

  @override
  List<Object?> get props => [comboId, cantidad, precioCentavos, componentes];
}
