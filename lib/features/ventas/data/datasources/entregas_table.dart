import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `entrega` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.entrega` del cloud (`backend-supabase`, migración 0001), con las
/// diferencias de motor de [Ventas]: fechas en epoch ms UTC, sin claves foráneas y sin defaults de
/// servidor. `stock_inconsistente` (migración 0118) la pone el servidor y el push la descarta: la app
/// no la escribe y no está acá.
///
/// **Una fila por producto de la venta** (no por renglón): al entregar un combo hay una fila por
/// componente, con su cantidad (migración 0056). [pendiente] dice si lo que cuenta la fila ya se
/// entregó (`false`, con [fechaEntrega]) o falta entregarlo (`true`, sin fecha). La entrega inmediata
/// (HU-VEN-002) crea las filas ya entregadas; las pendientes llegan con la entrega diferida
/// (HU-VEN-003).
///
/// **Sin dato del cliente** (ADR-004): cuelga de la venta por un id opaco.
@DataClassName('EntregaFila')
@TableIndex(name: 'entrega_venta_idx', columns: {#ventaId})
class Entregas extends Table {
  @override
  String get tableName => 'entrega';

  TextColumn get id => text()();

  TextColumn get ventaId => text()();

  TextColumn get productoId => text()();

  /// Cuántas unidades cuenta la fila; siempre 1 o más.
  IntColumn get cantidad => integer()();

  /// Cuándo se entregó de verdad; `null` mientras la fila está pendiente.
  IntColumn get fechaEntrega => integer().nullable().map(const FechaUtcConverter())();

  /// `true` = falta entregarlo (el valor por defecto del servidor); `false` = ya se entregó.
  BoolColumn get pendiente => boolean().withDefault(const Constant(true))();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6).
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (cantidad > 0)'];
}
