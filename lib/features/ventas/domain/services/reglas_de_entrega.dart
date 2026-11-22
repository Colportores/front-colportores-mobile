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

  /// Qué grupo de lo pendiente de una venta es de cada una de sus citas de entrega vivas (decisión de
  /// Cristian del 11/11, «Entrega cita»: una cita viva por cada grupo de libros diferido).
  ///
  /// Un **grupo** son las filas pendientes de la venta con la misma `entrega.fecha_prevista` (el dato
  /// que ya sube por renglón): la cita de un grupo es la que está programada a esa misma hora. Las
  /// fechas van en milisegundos desde la época; `null` es «sin fecha».
  ///
  /// - [citas]: `(id, fecha)` de las citas vivas, de la más antigua a la más nueva.
  /// - [fechas]: las fechas de lo pendiente (puede repetir; el orden es el de las filas).
  ///
  /// Devuelve, por id de cita, la fecha de su grupo; una cita sin grupo no figura. Primero va cada
  /// cita a su misma hora; una que no coincide con ninguna (movida fuera del teléfono, o de antes de
  /// que la fecha se moviera con la cita) toma, por orden, un grupo con fecha que quedó sin cita. Un
  /// grupo sin fecha no tiene cita.
  static Map<String, int?> repartirCitas(
    List<({String id, int fecha})> citas,
    Iterable<int?> fechas,
  ) {
    final libres = <int>[];
    for (final f in fechas) {
      if (f != null && !libres.contains(f)) libres.add(f);
    }
    final reparto = <String, int?>{};
    final sinCoincidir = <String>[];
    for (final c in citas) {
      if (libres.remove(c.fecha)) {
        reparto[c.id] = c.fecha;
      } else {
        sinCoincidir.add(c.id);
      }
    }
    for (final id in sinCoincidir) {
      if (libres.isEmpty) break;
      reparto[id] = libres.removeAt(0);
    }
    return reparto;
  }
}
