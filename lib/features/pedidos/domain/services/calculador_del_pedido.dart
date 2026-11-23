import '../entities/armado_del_pedido.dart';

/// Las cuentas de la pantalla de armar el pedido (37A): cuánto vale lo armado, cómo queda la deuda con
/// el pedido y si pasa el límite. Dart puro.
abstract final class CalculadorDelPedido {
  /// Lo que cuesta pedir [cantidades] (`productoId → unidades`) a los precios de compra de [productos]. Lo
  /// que no es un producto conocido no suma (no se puede pedir).
  static int montoDe(Map<String, int> cantidades, Iterable<ProductoPedible> productos) {
    var total = 0;
    for (final p in productos) {
      final n = cantidades[p.id] ?? 0;
      if (n > 0) total += n * p.precioDeCompraCentavos;
    }
    return total;
  }

  /// La deuda con el pedido incluido.
  static int deudaConPedido(SituacionDelColportor situacion, int montoDelPedido) =>
      situacion.deudaActualCentavos + montoDelPedido;

  /// El pedido «supera el límite» si la deuda con él pasa del límite de la campaña; **justo en el límite no
  /// lo supera** (esquema-datos §campania). Sin límite no hay aviso. Un pedido vacío no avisa.
  static bool superaElLimite(SituacionDelColportor situacion, int montoDelPedido) {
    final limite = situacion.limiteDeudaCentavos;
    if (limite == null || montoDelPedido <= 0) return false;
    return deudaConPedido(situacion, montoDelPedido) > limite;
  }

  /// Cuánto pasa del límite; 0 si no lo supera.
  static int superaPor(SituacionDelColportor situacion, int montoDelPedido) {
    final limite = situacion.limiteDeudaCentavos;
    if (!superaElLimite(situacion, montoDelPedido)) return 0;
    return deudaConPedido(situacion, montoDelPedido) - limite!;
  }
}
