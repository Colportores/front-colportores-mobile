import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `entrega` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.entrega` del cloud (`backend-supabase`, migraciones 0001 y 0068), con las
/// diferencias de motor de [Ventas]: fechas en epoch ms UTC, sin claves foráneas y sin defaults de
/// servidor. `stock_inconsistente` (migración 0118) la pone el servidor y la app no la escribe: no
/// está acá.
///
/// **Una fila por producto de la venta** (no por ítem): al entregar un combo hay una fila por
/// componente, con su cantidad (migración 0056). [pendiente] dice si lo que la fila cuenta ya se
/// entregó (`false`, con [fechaEntrega]) o falta entregarlo (`true`, sin fecha). La entrega inmediata
/// (HU-VEN-002) crea las filas de todo lo vendido: las de lo que se entrega ahora ya entregadas y las
/// de lo que la colportora destildó, pendientes.
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

  /// Cuándo se acordó entregar (backend 0068, HU-VEN-003); `null` si no hay fecha: la entrega
  /// inmediata no la tiene y una entrega pendiente puede quedar sin fecha. La cita de esa fecha es una
  /// fila de `agenda` tipo `ENTREGA`.
  IntColumn get fechaPrevista => integer().nullable().map(const FechaUtcConverter())();

  /// Cuándo se entregó de verdad (la fecha REAL; la acordada es [fechaPrevista]); `null` mientras la
  /// fila está pendiente.
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
