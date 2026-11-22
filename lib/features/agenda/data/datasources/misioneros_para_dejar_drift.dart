import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../catalogo/domain/entities/catalogo_local.dart' show CategoriaDeProducto;
import '../../domain/entities/misionero_dejado.dart';
import '../../domain/services/misioneros_para_dejar.dart';

/// [MisionerosParaDejar] sobre la réplica local del catálogo (`producto`, HU-CAT-007): la categoría
/// MISIONEROS es la única que el servidor acepta en `visita_misionero` (backend-supabase 0160).
final class MisionerosParaDejarDrift implements MisionerosParaDejar {
  MisionerosParaDejarDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<MisioneroParaDejar>> leer() async {
    final filas =
        await (_db.select(_db.productos)
              ..where(
                (p) =>
                    p.categoria.equals(CategoriaDeProducto.misioneros.codigo) &
                    p.deletedAt.isNull(),
              )
              ..orderBy([(p) => OrderingTerm.asc(p.nombre), (p) => OrderingTerm.asc(p.id)]))
            .get();
    return [for (final p in filas) MisioneroParaDejar(productoId: p.id, nombre: p.nombre)];
  }
}
