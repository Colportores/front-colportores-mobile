import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `stock` de la DB local: el inventario en mano del colportor, una fila por producto
/// (HU-STK-004, «Consultar mi stock», que se ve también sin internet). Réplica de **solo lectura**
/// (contrato-sync-engine §2, política `pull`, sin Realtime): la escribe el servidor al recibir un
/// pedido, al entregar, al devolver y al transferir, y el teléfono muestra lo que dice el servidor.
/// La app nunca la escribe: no descuenta localmente al vender o entregar sin conexión.
///
/// Misma forma que `public.stock` (backend-supabase 0067), con las diferencias del motor de
/// siempre (ver `Ubicaciones`): fechas en epoch ms UTC, sin claves foráneas ni defaults de
/// servidor y **sin el `UNIQUE (usuario_id, producto_id)`**: un índice único local podría frenar un
/// delta válido, y el servidor ya lo garantiza. `usuario_id` es siempre el del propio colportor
/// (backend-supabase 0145: el pull baja solo las filas del dueño).
///
/// `cantidad_disponible` **no tiene restricción de signo, a propósito** (S46): entregar más de lo
/// registrado se permite y queda como inconsistencia, así que puede ser negativa.
@DataClassName('StockFila')
@TableIndex(name: 'stock_usuario_idx', columns: {#usuarioId})
class Stocks extends Table {
  @override
  String get tableName => 'stock';

  TextColumn get id => text()();

  /// El colportor dueño del inventario.
  TextColumn get usuarioId => text()();

  TextColumn get productoId => text()();

  /// Unidades que tiene. Puede ser negativa (S46).
  IntColumn get cantidadDisponible => integer().withDefault(const Constant(0))();

  /// Unidades apartadas (por ejemplo, para una transferencia por autorizar). Nunca negativa.
  IntColumn get cantidadReservada => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: una fila dada de baja deja de contar, pero el delta la trae como tombstone para
  /// que el teléfono no conserve una cantidad vieja.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (cantidad_reservada >= 0)'];
}
