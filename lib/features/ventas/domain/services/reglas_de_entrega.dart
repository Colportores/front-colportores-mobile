import '../entities/componente_vendido.dart';

/// Un renglón vendido, en lo único que la entrega necesita de él: un producto suelto
/// ([productoId] y [cantidad]) o un combo ([componentes] de **una** unidad, por [cantidad]
/// unidades).
typedef RenglonVendido = ({String? productoId, int cantidad, List<ComponenteVendido>? componentes});

/// Cuánto hay que entregar de una venta y si ya está todo entregado (HU-VEN-002).
///
/// La entrega es **una fila por producto**: un combo se entrega como una fila por componente, con
/// `cantidad del componente × unidades del combo` (backend 0056 y 0071). Si el mismo producto se
/// vendió en dos renglones, o suelto y dentro de un combo, es una sola cantidad.
abstract final class ReglasDeEntrega {
  /// Lo que se vendió, por producto y en el orden en que aparece por primera vez.
  static Map<String, int> cantidadesVendidas(Iterable<RenglonVendido> renglones) {
    final suma = <String, int>{};
    void sumar(String productoId, int cantidad) {
      if (cantidad <= 0) return;
      suma[productoId] = (suma[productoId] ?? 0) + cantidad;
    }

    for (final renglon in renglones) {
      final componentes = renglon.componentes;
      if (componentes != null) {
        for (final c in componentes) {
          sumar(c.productoId, c.cantidad * renglon.cantidad);
        }
      } else if (renglon.productoId != null) {
        sumar(renglon.productoId!, renglon.cantidad);
      }
    }
    return suma;
  }

  /// Lo que falta entregar: lo vendido menos lo ya [entregado], por producto y sin ceros. Entregar de
  /// más se permite (no hay stock en V1), así que un producto entregado de sobra no resta a otro.
  static Map<String, int> cantidadesFaltantes(
    Map<String, int> vendido,
    Map<String, int> entregado,
  ) => {
    for (final MapEntry(:key, :value) in vendido.entries)
      if (value > (entregado[key] ?? 0)) key: value - (entregado[key] ?? 0),
  };

  /// Está toda entregada: hay algo vendido y no falta nada. Una venta sin renglones no está
  /// «entregada»: no hay nada que decir de ella.
  static bool estaEntregada(Map<String, int> vendido, Map<String, int> entregado) =>
      vendido.isNotEmpty && cantidadesFaltantes(vendido, entregado).isEmpty;
}
