import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../domain/entities/productos_de_la_entrega.dart';
import '../../domain/repositories/fuente_de_productos_de_la_entrega.dart';

/// [FuenteDeProductosDeLaEntrega] sobre la réplica local del catálogo (`producto` y
/// `producto_coleccion`, HU-CAT-007), sin red: los nombres de lo que se vendió y la base de cada combo,
/// para las filas de «Entregar ahora» (27B·01, #432).
///
/// - Los productos y combos **dados de baja** también: la venta ya se hizo y sigue nombrándolos.
/// - La base de un combo son sus componentes vivos (`producto_coleccion` sin `deleted_at`), lo que la
///   colportora no elige. Un combo sin componentes en el teléfono no se agrupa: cada producto va en su
///   fila (nada se esconde).
/// - Un producto que el teléfono no conoce queda sin nombre (la pantalla dice «Producto sin nombre»),
///   nunca con uno inventado.
///
/// `Left` ([FailureEntregaNoDisponible], el aviso con «Reintentar») si no se pudo leer o si ningún
/// pull terminó todavía: sin catálogo no se sabe qué es cada cosa.
final class FuenteDeProductosDeLaEntregaLocal implements FuenteDeProductosDeLaEntrega {
  FuenteDeProductosDeLaEntregaLocal(this._db, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AppDatabase _db;
  final AppLogger _log;

  @override
  Future<Either<Failure, ProductosDeLaEntrega>> leer({
    required Set<String> productoIds,
    required Set<String> comboIds,
  }) async {
    try {
      final leido = await _db.transaction(() async {
        if ((await DriftSyncMeta(_db).read()).lastPullAt == null) return null;
        final nombres = <String, String>{};
        if (productoIds.isNotEmpty) {
          final filas = await (_db.select(
            _db.productos,
          )..where((p) => p.id.isIn(productoIds))).get();
          for (final p in filas) {
            nombres[p.id] = p.nombre;
          }
        }
        final base = <String, Set<String>>{};
        if (comboIds.isNotEmpty) {
          final componentes =
              await (_db.select(_db.productoColecciones)
                    ..where((c) => c.coleccionId.isIn(comboIds) & c.deletedAt.isNull())
                    ..orderBy([(c) => OrderingTerm.asc(c.id)]))
                  .get();
          for (final c in componentes) {
            base.putIfAbsent(c.coleccionId, () => <String>{}).add(c.productoId);
          }
        }
        return ProductosDeLaEntrega(nombres: nombres, baseDeCombos: base);
      });
      if (leido == null) {
        _log.warn(
          LogModulo.venta,
          'ENTREGA_PRODUCTOS_SIN_BAJAR',
          'el teléfono todavía no bajó el catálogo',
        );
        return const Left(FailureEntregaNoDisponible());
      }
      return Right(leido);
    } on Object catch (e) {
      _log.warn(LogModulo.venta, 'ENTREGA_PRODUCTOS_FAIL', 'no se pudo leer el catálogo', {
        'causa': e.runtimeType.toString(),
      });
      return const Left(FailureEntregaNoDisponible());
    }
  }
}
