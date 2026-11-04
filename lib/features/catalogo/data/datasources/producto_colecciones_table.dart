import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `producto_coleccion` de la DB local: qué productos lleva cada combo y cuántas unidades de
/// cada uno. Réplica de solo lectura del canal de catálogo (contrato-sync-engine §2, política
/// `pull`).
///
/// Misma forma que `public.producto_coleccion` después de backend-supabase 0056, con las
/// diferencias del motor de siempre (ver `Ubicaciones`). **Sin el `UNIQUE (producto_id,
/// coleccion_id)`**: la réplica aplica las filas del delta de a una y el servidor ya lo garantiza.
@DataClassName('ProductoColeccionFila')
@TableIndex(name: 'producto_coleccion_coleccion_idx', columns: {#coleccionId})
class ProductoColecciones extends Table {
  @override
  String get tableName => 'producto_coleccion';

  TextColumn get id => text()();

  TextColumn get productoId => text()();

  TextColumn get coleccionId => text()();

  /// Unidades del producto que lleva el combo (1 libro y 2 revistas = dos filas, con 1 y 2).
  IntColumn get cantidad => integer().withDefault(const Constant(1))();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: un componente quitado del combo deja de contar.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (cantidad > 0)'];
}
