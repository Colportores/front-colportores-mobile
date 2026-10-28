import '../entities/componente_vendido.dart';
import '../entities/linea_para_entregar.dart';
import '../entities/productos_de_la_entrega.dart';
import '../entities/venta_item.dart';

/// De los ítems de una venta a las filas de «Qué entregás» (27B·01).
///
/// - Un producto suelto es una fila: «Vida Feliz × 2».
/// - Un combo se abre: cada libro que eligió la colportora es una fila y lo que el combo lleva
///   siempre (su base, según el catálogo) se junta en una sola, «Base de la colección». Si el catálogo
///   no dice cuál es la base de ese combo, cada componente es su fila: nada se esconde.
/// - Las cantidades ya son las del ítem entero (unidades de la línea por lo que trae una unidad).
abstract final class ArmadorDeLineasDeEntrega {
  /// El nombre que se muestra de un producto que el catálogo no conoce.
  static const sinNombre = 'Producto sin nombre';

  static List<LineaParaEntregar> armar(List<VentaItem> items, ProductosDeLaEntrega catalogo) {
    String nombre(String productoId) => catalogo.nombres[productoId] ?? sinNombre;
    final filas = <LineaParaEntregar>[];
    for (final item in items) {
      if (item.estaBorrada) continue;
      final productoId = item.productoId;
      if (productoId != null) {
        filas.add(
          LineaParaEntregar(
            clave: 'i:${item.id}',
            nombre: nombre(productoId),
            titulo: _conCantidad(nombre(productoId), item.cantidad),
            productos: [ComponenteVendido(productoId: productoId, cantidad: item.cantidad)],
          ),
        );
        continue;
      }
      final componentes = [
        for (final c in item.componentes ?? const <ComponenteVendido>[])
          ComponenteVendido(productoId: c.productoId, cantidad: c.cantidad * item.cantidad),
      ];
      final base = catalogo.baseDeCombos[item.coleccionId] ?? const <String>{};
      final deLaBase = [
        for (final c in componentes)
          if (base.contains(c.productoId)) c,
      ];
      var n = 0;
      for (final c in componentes) {
        if (base.contains(c.productoId)) continue;
        filas.add(
          LineaParaEntregar(
            clave: 'i:${item.id}:${n++}',
            nombre: nombre(c.productoId),
            titulo: _conCantidad(nombre(c.productoId), c.cantidad),
            productos: [c],
          ),
        );
      }
      if (deLaBase.isNotEmpty) {
        final nombres = _lista([for (final c in deLaBase) nombre(c.productoId)]);
        filas.add(
          LineaParaEntregar(
            clave: 'i:${item.id}:base',
            nombre: nombres,
            titulo: nombres,
            detalle: 'Base de la colección',
            productos: deLaBase,
          ),
        );
      }
    }
    return filas;
  }

  static String _conCantidad(String nombre, int cantidad) => '$nombre × $cantidad';

  /// «A», «A y B», «A, B y C».
  static String _lista(List<String> nombres) => nombres.length < 2
      ? nombres.join()
      : '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
}
