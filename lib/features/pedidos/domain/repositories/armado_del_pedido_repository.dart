import '../entities/armado_del_pedido.dart';

/// De dónde sale lo que se ve al armar un pedido (37A) y que solo está en la base del teléfono: los
/// productos con su costo y su stock, y lo que falta entregar con el límite de la campaña.
abstract interface class ArmadoDelPedidoRepository {
  /// Los productos que se pueden pedir (con precio de compra y categoría conocida), por nombre, cada vez
  /// que cambia el catálogo o el stock de [colportorId].
  Stream<List<ProductoPedible>> observarProductos(String colportorId);

  /// `id → nombre` de todos los productos del catálogo, para nombrar las líneas de un pedido (también las de
  /// un producto que ya no se puede pedir).
  Stream<Map<String, String>> observarNombres();

  /// Lo que falta entregar y el límite de la campaña de [colportorId], cada vez que cambian. [hoy] es el
  /// día de calendario con el que se elige la campaña.
  Stream<ContextoLocalDelPedido> observarContexto(String colportorId, DateTime hoy);
}
