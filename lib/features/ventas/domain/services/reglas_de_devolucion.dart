import 'dart:math' as math;

import '../entities/componente_vendido.dart';
import '../entities/devolucion.dart';
import '../entities/venta_para_devolver.dart';
import 'reglas_de_venta.dart';

/// Las reglas puras de una devolución (HU-VEN-004, ADR-002), sin pantalla ni base: la ventana de 72 h,
/// qué libros salen de lo que se elige, cuánto vale lo devuelto y qué se hace con la plata de más.
abstract final class ReglasDeDevolucion {
  /// Cuánto tiempo tiene la colportora, desde la venta, para registrar una devolución. Pasado ese
  /// plazo la registra el coordinador (HU-VEN-004, escenario «Devolución más allá de 72h»).
  static const ventana = Duration(hours: 72);

  /// Lo más largo que puede ser el motivo: el mismo tope del servidor (migración 0136) y del motivo
  /// del monto a mano.
  static const largoMaximoMotivo = ReglasDeVenta.largoMaximoMotivo;

  /// El último instante en que la colportora puede registrar la devolución de una venta hecha en
  /// [fechaDeLaVenta].
  static DateTime limiteDelPlazo(DateTime fechaDeLaVenta) => fechaDeLaVenta.add(ventana);

  /// Pasaron más de 72 h desde la venta. A las 72 h justas todavía se puede.
  static bool estaFueraDePlazo(DateTime fechaDeLaVenta, DateTime ahora) =>
      ahora.isAfter(limiteDelPlazo(fechaDeLaVenta));

  /// El motivo listo para guardar: sin espacios ni saltos de línea en los bordes, `null` si queda en
  /// blanco y cortado en [largoMaximoMotivo] puntos de código (como el motivo del monto a mano).
  static String? motivo(String? texto) => texto == null ? null : ReglasDeVenta.motivo(texto);

  /// Cuántas unidades del renglón [ventaItemId] ya volvieron según los libros [devueltos] (los de
  /// todas las devoluciones vivas de la venta; los de otros renglones no cuentan).
  ///
  /// - Un producto suelto: las unidades de su libro devueltas de ese renglón.
  /// - Un combo: las veces que volvió **entero**, es decir, las que alcanzan todos sus componentes
  ///   (cada uno por su cantidad). Un combo devuelto a medias no cuenta como unidad devuelta.
  static int unidadesDevueltas({
    required String ventaItemId,
    required String? productoId,
    required List<ComponenteVendido>? componentes,
    required Iterable<ProductoDevuelto> devueltos,
  }) {
    final delRenglon = devueltos.where((d) => d.ventaItemId == ventaItemId);
    if (componentes == null) {
      return delRenglon
          .where((d) => d.productoId == productoId)
          .fold(0, (suma, d) => suma + d.cantidad);
    }
    final porUnidad = <String, int>{};
    for (final c in componentes) {
      if (c.cantidad > 0) porUnidad[c.productoId] = (porUnidad[c.productoId] ?? 0) + c.cantidad;
    }
    if (porUnidad.isEmpty) return 0;
    var unidades = -1;
    for (final MapEntry(:key, :value) in porUnidad.entries) {
      final devuelto = delRenglon
          .where((d) => d.productoId == key)
          .fold(0, (s, d) => s + d.cantidad);
      final enteras = devuelto ~/ value;
      unidades = unidades < 0 ? enteras : math.min(unidades, enteras);
    }
    return math.max(0, unidades);
  }

  /// Lo que vuelve por producto, sumando todos los renglones (para saber cuánto queda por entregar).
  static Map<String, int> librosPorProducto(Iterable<ProductoDevuelto> devueltos) {
    final suma = <String, int>{};
    for (final d in devueltos) {
      suma[d.productoId] = (suma[d.productoId] ?? 0) + d.cantidad;
    }
    return suma;
  }

  /// Los libros que vuelven al devolver [unidades] del renglón [renglon]: el libro del suelto, o uno
  /// por cada componente del combo con su cantidad por las unidades. Vacío con 0 unidades.
  static List<ProductoDevuelto> librosDe(RenglonDeLaVenta renglon, int unidades) {
    if (unidades <= 0) return const [];
    final componentes = renglon.componentes;
    if (componentes == null) {
      final productoId = renglon.productoId;
      return productoId == null
          ? const []
          : [
              ProductoDevuelto(
                productoId: productoId,
                ventaItemId: renglon.ventaItemId,
                cantidad: unidades,
              ),
            ];
    }
    // Un mismo libro dos veces en el combo es un solo elemento (el par libro-renglón no se repite).
    final porLibro = <String, int>{};
    for (final c in componentes) {
      if (c.cantidad > 0) porLibro[c.productoId] = (porLibro[c.productoId] ?? 0) + c.cantidad;
    }
    return [
      for (final MapEntry(:key, :value) in porLibro.entries)
        ProductoDevuelto(
          productoId: key,
          ventaItemId: renglon.ventaItemId,
          cantidad: value * unidades,
        ),
    ];
  }

  /// Las unidades elegidas, ajustadas a lo que hay: sin renglones que no existen, sin ceros y sin
  /// pasar de lo que todavía se puede devolver de cada uno.
  static Map<String, int> ajustar(VentaParaDevolver venta, Map<String, int> elegidas) => {
    for (final r in venta.renglones)
      if (math.min(elegidas[r.ventaItemId] ?? 0, r.disponibles) > 0)
        r.ventaItemId: math.min(elegidas[r.ventaItemId]!, r.disponibles),
  };

  /// ¿Lo elegido es algo que se puede registrar tal cual? Alguna unidad, solo renglones de la venta y
  /// nunca más de lo que queda por devolver de cada uno.
  static bool esValida(VentaParaDevolver venta, Map<String, int> elegidas) {
    final ids = {for (final r in venta.renglones) r.ventaItemId: r};
    var alguna = false;
    for (final MapEntry(:key, :value) in elegidas.entries) {
      if (value == 0) continue;
      final renglon = ids[key];
      if (renglon == null || value < 0 || value > renglon.disponibles) return false;
      alguna = true;
    }
    return alguna;
  }

  /// Los libros que salen de lo elegido, renglón por renglón en el orden de la venta.
  static List<ProductoDevuelto> productosDe(VentaParaDevolver venta, Map<String, int> elegidas) => [
    for (final r in venta.renglones)
      ...librosDe(r, math.min(elegidas[r.ventaItemId] ?? 0, r.disponibles)),
  ];

  /// Cómo queda la venta con lo [elegidas] (ya ajustado con [ajustar]): lo que se queda el cliente,
  /// lo que pagó de más y lo que le falta pagar.
  static CuentaDeLaDevolucion cuenta(VentaParaDevolver venta, Map<String, int> elegidas) {
    final validas = ajustar(venta, elegidas);
    var unidades = 0;
    var valor = 0;
    var sobran = 0;
    for (final r in venta.renglones) {
      final n = validas[r.ventaItemId] ?? 0;
      unidades += n;
      valor += n * r.precioUnitarioCentavos;
      sobran += r.disponibles - n;
    }
    final esTotal = unidades > 0 && sobran == 0;
    // Devolver todo deja la venta en cero aunque su monto no coincida con la suma de los renglones.
    final seQueda = esTotal ? 0 : math.max(0, venta.seQuedaConCentavos - valor);
    final yaPago = venta.yaPagoCentavos;
    return CuentaDeLaDevolucion(
      unidades: unidades,
      valorCentavos: valor,
      seQuedaConCentavos: seQueda,
      yaPagoCentavos: yaPago,
      pagoDeMasCentavos: math.max(0, yaPago - seQueda - venta.retenidoCentavos),
      saldoNuevoCentavos: math.max(0, seQueda - yaPago),
      esTotal: esTotal,
    );
  }

  /// Qué guarda la devolución con la plata de más ([pagoDeMas]) según lo que eligió la colportora:
  /// lo retenido y lo reembolsado en el momento. Sin plata de más no se guarda nada de las dos, aunque
  /// haya una opción. Devuelve `null` si hay plata de más y no eligió: la elección es obligatoria.
  static ({int retenido, int? reembolsado})? destinoDeLaDiferencia(
    int pagoDeMas,
    QueHacerConLaDiferencia? opcion,
  ) {
    if (pagoDeMas <= 0) return (retenido: 0, reembolsado: null);
    return switch (opcion) {
      null => null,
      QueHacerConLaDiferencia.devolverAhora => (retenido: 0, reembolsado: pagoDeMas),
      QueHacerConLaDiferencia.retener => (retenido: pagoDeMas, reembolsado: null),
      QueHacerConLaDiferencia.devolverDespues => (retenido: 0, reembolsado: null),
    };
  }
}
