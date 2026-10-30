import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/devolucion.dart';

/// DTO de [Devolucion]: la fila entera que se encola para el sync. [toJson] usa los nombres de columna
/// de `public.devolucion` (`backend-supabase`, migraciones 0108, 0136 y 0142) y las fechas en
/// ISO-8601 UTC. No lleva `colportor_id`: lo pone el servidor desde el JWT y el push lo descarta
/// (contrato §2.4). Un test fija la lista exacta de claves.
///
/// **Sin dato del cliente** (ADR-004): `venta_id` y los ids de producto y de renglón son opacos. La
/// única prosa que sube es el `motivo`, por decisión explícita de Cristian (27/10).
abstract final class DevolucionModel {
  static Map<String, Object?> toJson(Devolucion devolucion) => {
    'id': devolucion.id,
    'venta_id': devolucion.ventaId,
    'productos_devueltos': productosAJson(devolucion.productos),
    'dinero_retenido': devolucion.dineroRetenidoCentavos,
    'monto_reembolsado': devolucion.montoReembolsadoCentavos,
    'motivo': devolucion.motivo,
    'fecha_devolucion': devolucion.fechaDevolucion.toIso8601String(),
    ...auditoriaAJson(devolucion.auditoria),
  };

  /// `[{producto_id, cantidad, venta_item_id}]`: las tres claves y nada más (migración 0136).
  static List<Map<String, Object?>> productosAJson(List<ProductoDevuelto> productos) => [
    for (final p in productos)
      {'producto_id': p.productoId, 'cantidad': p.cantidad, 'venta_item_id': p.ventaItemId},
  ];

  /// Inversa de [productosAJson]. Un elemento mal formado (sin alguna de las tres claves) se salta:
  /// leer una devolución nunca revienta por una fila rara.
  static List<ProductoDevuelto> productosDesdeJson(List<Object?> json) => [
    for (final p in json)
      if (p is Map<String, Object?> &&
          p['producto_id'] is String &&
          p['venta_item_id'] is String &&
          p['cantidad'] is num)
        ProductoDevuelto(
          productoId: p['producto_id']! as String,
          cantidad: (p['cantidad']! as num).toInt(),
          ventaItemId: p['venta_item_id']! as String,
        ),
  ];
}
