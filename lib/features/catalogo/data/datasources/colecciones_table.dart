import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `coleccion` de la DB local: los combos (una colección con precio propio, HU-CAT-009).
/// Réplica de solo lectura del canal de catálogo (contrato-sync-engine §2, política `pull`).
///
/// Misma forma que `public.coleccion` después de backend-supabase 0071, con las diferencias del
/// motor de siempre (ver `Ubicaciones`). Sus componentes están en `producto_coleccion`.
@DataClassName('ColeccionFila')
class Colecciones extends Table {
  @override
  String get tableName => 'coleccion';

  TextColumn get id => text()();

  TextColumn get nombre => text()();

  /// Cuántos libros del catálogo elige quien vende, además de lo fijo del combo. `0` = combo fijo.
  IntColumn get librosAElegir => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: un combo dado de baja deja de ofrecerse.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (libros_a_elegir >= 0)'];
}
