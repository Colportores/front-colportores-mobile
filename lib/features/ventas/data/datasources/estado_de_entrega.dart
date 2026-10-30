import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/services/reglas_de_entrega.dart';
import '../models/venta_model.dart';

/// Qué se vendió y qué se entregó de una venta, leído de las tablas locales: **la única definición**
/// que usan la entrega inmediata (`EntregaLocalDataSourceDrift`, HU-VEN-002) y el color de la casa
/// (`HouseStatusUpdaterDrift`, R-UB08), para que nunca cuenten cosas distintas.
///
/// Cuenta lo vendido de los renglones vivos y lo entregado de las filas de `entrega` vivas y ya
/// entregadas (`pendiente = 0`); una fila dada de baja o todavía pendiente no cuenta.
abstract final class EstadoDeEntrega {
  /// Lo vendido de [ventaId], por producto (ver [ReglasDeEntrega.cantidadesVendidas]).
  static Future<Map<String, int>> vendidoDe(AppDatabase db, String ventaId) async {
    final filas =
        await (db.select(db.ventaItems)
              ..where((i) => i.ventaId.equals(ventaId) & i.deletedAt.isNull())
              ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
            .get();
    return ReglasDeEntrega.cantidadesVendidas([
      for (final fila in filas)
        (
          productoId: fila.productoId,
          cantidad: fila.cantidad,
          componentes: fila.coleccionId == null
              ? null
              : VentaItemModel.componentesDesdeJson(fila.componentes) ?? const [],
        ),
    ]);
  }

  /// Lo ya entregado de [ventaId], por producto.
  static Future<Map<String, int>> entregadoDe(AppDatabase db, String ventaId) async {
    final filas =
        await (db.select(db.entregas)..where(
              (e) => e.ventaId.equals(ventaId) & e.deletedAt.isNull() & e.pendiente.equals(false),
            ))
            .get();
    final suma = <String, int>{};
    for (final fila in filas) {
      suma[fila.productoId] = (suma[fila.productoId] ?? 0) + fila.cantidad;
    }
    return suma;
  }

  /// Está toda entregada ([ReglasDeEntrega.estaEntregada]).
  static Future<bool> estaEntregada(AppDatabase db, String ventaId) async =>
      ReglasDeEntrega.estaEntregada(await vendidoDe(db, ventaId), await entregadoDe(db, ventaId));
}
