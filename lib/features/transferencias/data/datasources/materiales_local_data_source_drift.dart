import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../catalogo/domain/entities/catalogo_local.dart' show CategoriaDeProducto;
import '../../../catalogo/domain/entities/item_de_precio.dart' show CategoriaDePrecios;
import '../../domain/entities/material_de_transferencia.dart';

/// Lee del teléfono lo que la pantalla «Pedir transferencia» necesita del catálogo y del stock: los
/// materiales que se pueden pedir y cómo se llama cada producto (para mostrar las líneas de una
/// transferencia ya pedida). Solo lee: las dos tablas son réplicas del servidor.
final class MaterialesLocalDataSourceDrift {
  const MaterialesLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  /// Los productos vivos que se ofrecen (libros, misioneros y revistas: lo que tiene una categoría que
  /// se vende), con lo que [colportorId] tiene de cada uno, ordenados por nombre. Cambia con el catálogo
  /// y con el stock.
  Stream<List<MaterialDeTransferencia>> observar(String colportorId) {
    final productos = _db.productos;
    final stocks = _db.stocks;
    final consulta =
        _db.select(productos).join([
            leftOuterJoin(
              stocks,
              stocks.productoId.equalsExp(productos.id) &
                  stocks.usuarioId.equals(colportorId) &
                  stocks.deletedAt.isNull(),
            ),
          ])
          ..where(productos.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(productos.nombre), OrderingTerm.asc(productos.id)]);
    return consulta.watch().map((filas) {
      final materiales = <MaterialDeTransferencia>[];
      for (final fila in filas) {
        final producto = fila.readTable(productos);
        final categoria = CategoriaDeProducto.desdeCodigo(producto.categoria);
        if (!categoria.seVende) continue;
        materiales.add(
          MaterialDeTransferencia(
            id: producto.id,
            nombre: producto.nombre,
            categoria: switch (categoria) {
              CategoriaDeProducto.misioneros => CategoriaDePrecios.misioneros,
              CategoriaDeProducto.revistas => CategoriaDePrecios.revistas,
              _ => CategoriaDePrecios.libros,
            },
            tengo: fila.readTableOrNull(stocks)?.cantidadDisponible ?? 0,
            esBonificable: producto.esBonificable,
          ),
        );
      }
      return materiales;
    });
  }

  /// `id → nombre` de **todos** los productos, también los dados de baja: una transferencia que ya se
  /// pidió sigue nombrando lo que pidió.
  Stream<Map<String, String>> observarNombres() =>
      _db.select(_db.productos).watch().map((filas) => {for (final p in filas) p.id: p.nombre});
}
