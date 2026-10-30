import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/devolucion.dart';
import '../../domain/entities/venta_para_devolver.dart';
import '../../domain/services/reglas_de_devolucion.dart';
import '../models/devolucion_model.dart';
import '../models/venta_model.dart';

/// Lo que las devoluciones vivas de una venta cambian en sus cuentas.
final class ResumenDeDevoluciones {
  const ResumenDeDevoluciones({
    this.productos = const [],
    this.valorCentavos = 0,
    this.reembolsadoCentavos = 0,
    this.retenidoCentavos = 0,
    this.ultimaFecha,
    this.todoDevuelto = false,
  });

  /// La venta sin ninguna devolución.
  static const ninguna = ResumenDeDevoluciones();

  /// Todos los libros que volvieron, de todas las devoluciones vivas.
  final List<ProductoDevuelto> productos;

  /// Lo que valen las unidades devueltas, en centavos.
  final int valorCentavos;

  /// Lo que ya se le devolvió al cliente en el momento.
  final int reembolsadoCentavos;

  /// Lo que la colportora retuvo.
  final int retenidoCentavos;

  /// Cuándo se registró la última devolución viva; `null` si no hay ninguna.
  final DateTime? ultimaFecha;

  /// Volvió todo lo vendido (cada renglón vivo, por completo): la venta se queda en cero aunque su
  /// monto no coincida con la suma de los renglones (un monto puesto a mano).
  final bool todoDevuelto;

  bool get hayDevoluciones => productos.isNotEmpty;

  /// Lo que volvió por producto, sumando los renglones.
  Map<String, int> get librosPorProducto => ReglasDeDevolucion.librosPorProducto(productos);

  /// Las cuentas de una venta de [montoTotalCentavos] con [cobradoCentavos] cobrados y estas
  /// devoluciones.
  CuentaDeLaVenta cuentaDe({required int montoTotalCentavos, required int cobradoCentavos}) =>
      CuentaDeLaVenta(
        montoTotalCentavos: montoTotalCentavos,
        cobradoCentavos: cobradoCentavos,
        devueltoCentavos: todoDevuelto ? montoTotalCentavos : valorCentavos,
        reembolsadoCentavos: reembolsadoCentavos,
        retenidoCentavos: retenidoCentavos,
      );
}

/// Qué se devolvió de una venta, leído de las tablas locales: **la única definición** que usan el saldo
/// (`CobranzaLocalDataSourceDrift`, HU-COB-005), la entrega (`EstadoDeEntrega`), el color de la casa
/// (`HouseStatusUpdaterDrift`, R-UB08) y la devolución misma (`DevolucionLocalDataSourceDrift`), para
/// que nunca cuenten cosas distintas.
///
/// Cuenta solo las devoluciones vivas (`deleted_at IS NULL`): la baja de una devolución mal cargada
/// vuelve la venta a como estaba. El valor sale de los renglones vivos de la venta.
abstract final class EstadoDeDevolucion {
  /// Las ventas por consulta: SQLite limita las variables de una sentencia.
  static const _porConsulta = 400;

  /// El resumen de cada venta de [ventaIds] que tiene alguna devolución viva. Las que no tienen no
  /// aparecen en el mapa (usar [ResumenDeDevoluciones.ninguna]).
  static Future<Map<String, ResumenDeDevoluciones>> resumenesDe(
    AppDatabase db,
    Iterable<String> ventaIds,
  ) async {
    final ids = ventaIds.toSet().toList();
    final salida = <String, ResumenDeDevoluciones>{};
    for (var desde = 0; desde < ids.length; desde += _porConsulta) {
      final lote = ids.sublist(desde, (desde + _porConsulta).clamp(0, ids.length));
      final filas =
          await (db.select(db.devoluciones)
                ..where((d) => d.ventaId.isIn(lote) & d.deletedAt.isNull())
                ..orderBy([(d) => OrderingTerm.asc(d.createdAt), (d) => OrderingTerm.asc(d.id)]))
              .get();
      if (filas.isEmpty) continue;
      final porVenta = <String, List<DevolucionFila>>{};
      for (final fila in filas) {
        (porVenta[fila.ventaId] ??= []).add(fila);
      }
      final renglones = await _renglonesDe(db, porVenta.keys.toList());
      for (final MapEntry(:key, :value) in porVenta.entries) {
        salida[key] = _resumir(value, renglones[key] ?? const []);
      }
    }
    return salida;
  }

  /// El resumen de [ventaId]; [ResumenDeDevoluciones.ninguna] si no devolvió nada.
  static Future<ResumenDeDevoluciones> resumenDe(AppDatabase db, String ventaId) async =>
      (await resumenesDe(db, [ventaId]))[ventaId] ?? ResumenDeDevoluciones.ninguna;

  /// Los libros devueltos de una devolución, tal como se guardaron.
  static List<ProductoDevuelto> productosDe(DevolucionFila fila) =>
      DevolucionModel.productosDesdeJson(fila.productosDevueltos);

  /// Los renglones vivos de cada venta de [ventaIds], en el orden de la venta.
  static Future<Map<String, List<VentaItemFila>>> _renglonesDe(
    AppDatabase db,
    List<String> ventaIds,
  ) async {
    final filas =
        await (db.select(db.ventaItems)
              ..where((i) => i.ventaId.isIn(ventaIds) & i.deletedAt.isNull())
              ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
            .get();
    final salida = <String, List<VentaItemFila>>{};
    for (final fila in filas) {
      (salida[fila.ventaId] ??= []).add(fila);
    }
    return salida;
  }

  static ResumenDeDevoluciones _resumir(
    List<DevolucionFila> devoluciones,
    List<VentaItemFila> renglones,
  ) {
    final productos = [for (final d in devoluciones) ...productosDe(d)];
    var valor = 0;
    var todo = renglones.isNotEmpty;
    for (final r in renglones) {
      final unidades = ReglasDeDevolucion.unidadesDevueltas(
        ventaItemId: r.id,
        productoId: r.productoId,
        componentes: r.coleccionId == null
            ? null
            : VentaItemModel.componentesDesdeJson(r.componentes) ?? const [],
        devueltos: productos,
      );
      valor += (unidades < r.cantidad ? unidades : r.cantidad) * r.precioUnitario;
      if (unidades < r.cantidad) todo = false;
    }
    return ResumenDeDevoluciones(
      productos: productos,
      valorCentavos: valor,
      reembolsadoCentavos: devoluciones.fold(0, (s, d) => s + (d.montoReembolsado ?? 0)),
      retenidoCentavos: devoluciones.fold(0, (s, d) => s + d.dineroRetenido),
      ultimaFecha: devoluciones
          .map((d) => d.fechaDevolucion)
          .reduce((a, b) => b.isAfter(a) ? b : a),
      todoDevuelto: todo,
    );
  }
}
