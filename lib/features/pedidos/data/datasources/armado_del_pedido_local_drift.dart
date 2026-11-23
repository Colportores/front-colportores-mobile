import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/dia_de_calendario.dart';
import '../../../catalogo/domain/entities/catalogo_local.dart';
import '../../domain/entities/armado_del_pedido.dart';
import '../../domain/repositories/armado_del_pedido_repository.dart';

/// Lo que se ve al armar el pedido, leído de la DB cifrada: el catálogo con el costo de la casa editora, el
/// stock propio, las entregas pendientes y el límite de la campaña (HU-STK-009).
final class ArmadoDelPedidoLocalDrift implements ArmadoDelPedidoRepository {
  const ArmadoDelPedidoLocalDrift(this._db);

  final AppDatabase _db;

  /// Los días después del fin de la campaña en que todavía se puede pedir (HU-STK-009: «hasta el fin de la
  /// campaña más 15 días»).
  static const diasDeGraciaDespuesDelFin = 15;

  @override
  Stream<List<ProductoPedible>> observarProductos(String colportorId) {
    final consulta = _db.customSelect(
      'SELECT 1 AS cambio FROM producto UNION ALL SELECT 1 FROM stock',
      readsFrom: {_db.productos, _db.stocks},
    );
    return consulta.watch().asyncMap((_) => _productos(colportorId));
  }

  Future<List<ProductoPedible>> _productos(String colportorId) async {
    final filas =
        await (_db.select(_db.productos)
              ..where((p) => p.deletedAt.isNull() & p.precioBaseCompra.isNotNull())
              ..orderBy([(p) => OrderingTerm.asc(p.nombre), (p) => OrderingTerm.asc(p.id)]))
            .get();
    final stocks = {
      for (final s in await (_db.select(
        _db.stocks,
      )..where((s) => s.usuarioId.equals(colportorId) & s.deletedAt.isNull())).get())
        s.productoId: s.cantidadDisponible,
    };
    return [
      for (final p in filas)
        if (CategoriaDelPedido.de(CategoriaDeProducto.desdeCodigo(p.categoria)) != null &&
            (p.precioBaseCompra ?? 0) > 0)
          ProductoPedible(
            id: p.id,
            nombre: p.nombre,
            categoriaDelCatalogo: CategoriaDeProducto.desdeCodigo(p.categoria),
            precioDeCompraCentavos: p.precioBaseCompra!,
            stock: stocks[p.id] ?? 0,
            esBonificable: p.esBonificable,
          ),
    ];
  }

  @override
  Stream<Map<String, String>> observarNombres() =>
      _db.select(_db.productos).watch().map((filas) => {for (final p in filas) p.id: p.nombre});

  @override
  Stream<ContextoLocalDelPedido> observarContexto(String colportorId, DateTime hoy) {
    final consulta = _db.customSelect(
      'SELECT 1 AS cambio FROM entrega UNION ALL SELECT 1 FROM campania '
      'UNION ALL SELECT 1 FROM campania_colportor UNION ALL SELECT 1 FROM venta',
      readsFrom: {_db.entregas, _db.campanias, _db.campaniasColportor, _db.ventas},
    );
    return consulta.watch().asyncMap((_) => _contexto(colportorId, hoy));
  }

  Future<ContextoLocalDelPedido> _contexto(String colportorId, DateTime hoy) async {
    final e = _db.entregas;
    final v = _db.ventas;
    final unidades = e.cantidad.sum();
    final pendientes =
        await (_db.selectOnly(e).join([innerJoin(v, v.id.equalsExp(e.ventaId))])
              ..addColumns([unidades])
              ..where(
                e.pendiente.equals(true) &
                    e.deletedAt.isNull() &
                    v.deletedAt.isNull() &
                    v.colportorId.equals(colportorId),
              ))
            .map((fila) => fila.read(unidades) ?? 0)
            .getSingle();
    return ContextoLocalDelPedido(
      librosPorEntregar: pendientes,
      limiteDeudaCentavos: await _limiteDeLaCampania(colportorId, hoy),
    );
  }

  /// El límite de la campaña en la que la colportora puede pedir hoy: la inscripción viva con la campaña
  /// que ya empezó y todavía no pasó de su fin más [diasDeGraciaDespuesDelFin] días (la que empezó última
  /// si son varias) o, si no hay, la que está por empezar (se puede pedir desde el alta, aun antes del
  /// inicio). `null` si no hay ninguna o la campaña no tiene límite.
  Future<int?> _limiteDeLaCampania(String colportorId, DateTime hoy) async {
    final dia = diaDeCalendario(hoy);
    final c = _db.campanias;
    final i = _db.campaniasColportor;
    final filas = await (_db.select(c).join([
      innerJoin(i, i.campaniaId.equalsExp(c.id)),
    ])..where(i.usuarioId.equals(colportorId) & i.deletedAt.isNull() & c.deletedAt.isNull())).get();
    final campanias = [for (final f in filas) f.readTable(c)];
    final enVentana = [
      for (final f in campanias)
        if (f.fechaInicio.compareTo(dia) <= 0 && !_pasoLaGracia(f.fechaFin, dia)) f,
    ]..sort((a, b) => b.fechaInicio.compareTo(a.fechaInicio));
    if (enVentana.isNotEmpty) return enVentana.first.limiteDeuda;
    final porEmpezar = [
      for (final f in campanias)
        if (f.fechaInicio.compareTo(dia) > 0) f,
    ]..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    return porEmpezar.isEmpty ? null : porEmpezar.first.limiteDeuda;
  }

  /// [fin] más la gracia ya pasó. [fin] y [dia] son `aaaa-mm-dd`.
  static bool _pasoLaGracia(String? fin, String dia) {
    if (fin == null) return false;
    final f = fin.split('-').map(int.parse).toList();
    final limite = DateTime.utc(
      f[0],
      f[1],
      f[2],
    ).add(const Duration(days: diasDeGraciaDespuesDelFin));
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${limite.year.toString().padLeft(4, '0')}-${dos(limite.month)}-${dos(limite.day)}'
            .compareTo(dia) <
        0;
  }
}
