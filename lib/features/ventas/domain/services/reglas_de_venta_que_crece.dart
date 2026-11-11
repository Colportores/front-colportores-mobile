import '../entities/venta_abierta.dart';
import '../entities/venta_para_devolver.dart';

/// Las reglas puras de «Venta crece» (HU-VEN-001; decisiones de Cristian del 10/11, «Venta crece» y
/// «Venta cerrada», con los casos límite del agente de decisiones): a qué venta se le puede sumar otro
/// libro y cómo quedan el total y el saldo.
abstract final class ReglasDeVentaQueCrece {
  /// Si la venta está **abierta**: viva, con algo que el cliente se queda (no se devolvió todo) y con
  /// saldo o con algo por entregar. Una venta pagada y entregada, anulada (dada de baja) o con todo
  /// devuelto está cerrada: el libro que se pida después es una venta nueva.
  static bool estaAbierta({
    required bool borrada,
    required bool todoDevuelto,
    required CuentaDeLaVenta cuenta,
    required bool entregada,
  }) {
    if (borrada || todoDevuelto || cuenta.seQuedaConCentavos <= 0) return false;
    return cuenta.saldoCentavos > 0 || !entregada;
  }

  /// [abiertas] de la más reciente a la más vieja («¿A qué venta lo sumás?» viene con la más reciente
  /// elegida). A igual fecha, por id, para que el orden no dependa de la lectura.
  static List<VentaAbierta> masRecientePrimero(Iterable<VentaAbierta> abiertas) =>
      [...abiertas]..sort((a, b) {
        final porFecha = b.fecha.compareTo(a.fecha);
        return porFecha != 0 ? porFecha : b.ventaId.compareTo(a.ventaId);
      });

  /// El total de la venta después de sumar [sumadoCentavos]: lo que ya tenía más lo nuevo. Lo vendido
  /// antes no se recalcula.
  static int totalNuevo({required int anteriorCentavos, required int sumadoCentavos}) =>
      anteriorCentavos + sumadoCentavos;
}

/// Qué sigue de «Sumar un libro» según las ventas abiertas de la persona (42B·09A y 09B):
///
/// - [SinVentaAbierta]: no queda ninguna (se pagó y entregó mientras la hoja estaba abierta).
/// - [UnaVentaAbierta]: se suma ahí, sin preguntar («Se suma a la venta 0039»).
/// - [VariasVentasAbiertas]: «¿A qué venta lo sumás?», con la más reciente primero y elegida.
sealed class PasoVentaQueCrece {
  const PasoVentaQueCrece();

  static PasoVentaQueCrece de(Iterable<VentaAbierta> abiertas) {
    final lista = ReglasDeVentaQueCrece.masRecientePrimero(abiertas);
    return switch (lista.length) {
      0 => const SinVentaAbierta(),
      1 => UnaVentaAbierta(lista.single),
      _ => VariasVentasAbiertas(lista),
    };
  }
}

final class SinVentaAbierta extends PasoVentaQueCrece {
  const SinVentaAbierta();
}

final class UnaVentaAbierta extends PasoVentaQueCrece {
  const UnaVentaAbierta(this.venta);

  final VentaAbierta venta;
}

final class VariasVentasAbiertas extends PasoVentaQueCrece {
  const VariasVentasAbiertas(this.ventas);

  /// De la más reciente a la más vieja.
  final List<VentaAbierta> ventas;
}
