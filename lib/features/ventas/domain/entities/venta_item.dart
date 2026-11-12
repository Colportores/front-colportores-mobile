import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import 'componente_vendido.dart';

/// Línea de venta (esquema-datos.md §Operaciones de campo, tabla `venta_item`).
///
/// El dinero va en centavos como `int`, nunca `double` (flutter-clean-arch.md, regla 6) — mismo
/// criterio que [VentaItem.precioUnitarioCentavos] y `Venta.montoTotalCentavos`. El esquema no
/// dice si `subtotal` se deriva de `cantidad * precio_unitario` o puede diferir (ej. descuentos)
/// — se guarda el valor tal cual llega, sin asumir la fórmula.
class VentaItem extends Equatable {
  const VentaItem({
    required this.id,
    required this.ventaId,
    required this.productoId,
    this.coleccionId,
    this.componentes,
    required this.cantidad,
    required this.precioUnitarioCentavos,
    required this.subtotalCentavos,
    required this.auditoria,
  });

  final String id;

  /// FK a `venta.id`.
  final String ventaId;

  /// FK a `producto.id` (Catálogo, fuera del alcance de #8 — se referencia por id). `null` si el
  /// ítem es un combo: exactamente uno de [productoId] y [coleccionId] (backend 0056).
  final String? productoId;

  /// FK a `coleccion.id`: el combo vendido como un solo ítem; `null` si es un producto.
  final String? coleccionId;

  /// Lo que traía **una unidad** del combo al venderse (lo fijo y lo que eligió la colportora),
  /// copiado en el ítem: cambiar el combo después no toca la venta. Va en un combo y solo en un
  /// combo (backend 0071).
  final List<ComponenteVendido>? componentes;

  final int cantidad;

  /// Precio unitario en centavos (flutter-clean-arch.md, regla 6).
  final int precioUnitarioCentavos;

  /// Subtotal en centavos (flutter-clean-arch.md, regla 6).
  final int subtotalCentavos;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    ventaId,
    productoId,
    coleccionId,
    componentes,
    cantidad,
    precioUnitarioCentavos,
    subtotalCentavos,
    auditoria,
  ];
}
