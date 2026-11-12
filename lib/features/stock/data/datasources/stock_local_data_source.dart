import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Lectura del stock del colportor desde la DB local (HU-STK-004). Solo lee: la tabla `stock` es una
/// réplica del servidor y la app nunca la escribe (contrato-sync-engine §2, política `pull`).
///
/// La vista «Mi stock» (#512, espera diseño) se apoya en esto; hoy no hay pantalla que lo consuma.
class StockLocalDataSource {
  StockLocalDataSource(this._db);

  final AppDatabase _db;

  /// El stock vivo (sin bajas lógicas) del colportor [usuarioId], ordenado por producto, y cada vez
  /// que el pull lo cambia. El pull ya baja solo las filas del dueño; el filtro por [usuarioId]
  /// evita mezclar cuentas si en el mismo teléfono quedó el stock de otra sesión.
  Stream<List<StockFila>> observarDe(String usuarioId) {
    final consulta = _db.select(_db.stocks)
      ..where((s) => s.usuarioId.equals(usuarioId) & s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm.asc(s.productoId)]);
    return consulta.watch();
  }

  /// Lo que tiene el colportor [usuarioId] del producto [productoId], o `null` si el servidor no
  /// le registra stock de ese producto (no es lo mismo que cero).
  Future<StockFila?> deProducto(String usuarioId, String productoId) {
    final consulta = _db.select(_db.stocks)
      ..where(
        (s) =>
            s.usuarioId.equals(usuarioId) & s.productoId.equals(productoId) & s.deletedAt.isNull(),
      );
    return consulta.getSingleOrNull();
  }
}
