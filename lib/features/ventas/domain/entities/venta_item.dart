import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Línea de venta (esquema-datos.md §Operaciones de campo, tabla `venta_item`).
///
/// `precioUnitarioCentavos`/`subtotalCentavos`: mismo criterio que `Venta.montoTotalCentavos`
/// — el esquema no especifica el tipo de los montos; se usa `int` en centavos.
/// **Pendiente de confirmar** (ver PR). El esquema tampoco dice si `subtotal` se deriva de
/// `cantidad * precio_unitario` o puede diferir (ej. descuentos) — se guarda el valor tal cual
/// llega, sin asumir la fórmula.
class VentaItem extends Equatable {
  const VentaItem({
    required this.id,
    required this.ventaId,
    required this.productoId,
    required this.cantidad,
    required this.precioUnitarioCentavos,
    required this.subtotalCentavos,
    required this.auditoria,
  });

  final String id;

  /// FK a `venta.id`.
  final String ventaId;

  /// FK a `producto.id` (Catálogo, fuera del alcance de #8 — se referencia por id).
  final String productoId;

  final int cantidad;

  /// Pendiente de confirmar: ver doc comment de la clase.
  final int precioUnitarioCentavos;

  /// Pendiente de confirmar: ver doc comment de la clase.
  final int subtotalCentavos;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    ventaId,
    productoId,
    cantidad,
    precioUnitarioCentavos,
    subtotalCentavos,
    auditoria,
  ];
}
