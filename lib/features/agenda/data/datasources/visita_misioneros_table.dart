import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `visita_misionero` de la DB local cifrada: los misioneros que la colportora dejó en una
/// entrevista sin venta, un renglón por producto (paso «Lo que dejaste» de la hoja de término, #608).
///
/// Es la misma tabla que `public.visita_misionero` del cloud (backend-supabase 0160), con las
/// diferencias de motor de [Visitas]: fechas en epoch ms UTC, sin claves foráneas y sin defaults de
/// servidor. `colportor_id` lo fija el servidor desde el JWT y el push lo descarta: la app no lo
/// escribe y no está acá (el dueño es el de la visita).
///
/// No es una venta (decisión de Cristian, 03/11, «Talonario mis»): sin talonario ni monto. El servidor
/// descuenta el stock con un movimiento `SALIDA_MISIONERO`. Sin dato del cliente: cuelga de la visita
/// por un id opaco. Un solo renglón vivo por visita y producto, como el índice único del servidor.
@DataClassName('VisitaMisioneroFila')
@TableIndex(name: 'visita_misionero_visita_idx', columns: {#visitaId})
class VisitaMisioneros extends Table {
  @override
  String get tableName => 'visita_misionero';

  TextColumn get id => text()();

  /// La visita (la entrevista dada) en la que se dejaron.
  TextColumn get visitaId => text()();

  /// Un producto de categoría MISIONEROS.
  TextColumn get productoId => text()();

  /// Cuántos ejemplares: 1 o más.
  IntColumn get cantidad => integer()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6).
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (cantidad >= 1)'];
}
