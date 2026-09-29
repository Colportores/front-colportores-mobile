import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `espacio` de la DB local cifrada (esquema-datos.md §Modelo de Espacio, ADR-001): el punto
/// de contacto dentro de una ubicación.
///
/// Misma tabla que `public.espacio` del cloud (`backend-supabase`, migración 0001), con las
/// diferencias de motor de `ubicacion` ([FechaUtcConverter], sin defaults de servidor). Tampoco
/// lleva la clave foránea a `ubicacion`: el pull y la recuperación de dispositivo
/// (contrato-sync-engine §7) no garantizan que la ubicación llegue antes que sus espacios.
@DataClassName('EspacioFila')
@TableIndex(name: 'espacio_ubicacion_idx', columns: {#ubicacionId})
class Espacios extends Table {
  @override
  String get tableName => 'espacio';

  TextColumn get id => text()();

  TextColumn get ubicacionId => text()();

  /// `NULL` en el espacio único de una casa o un negocio (ADR-001).
  TextColumn get numeroDepto => text().nullable()();

  TextColumn get piso => text().nullable()();

  TextColumn get descripcion => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
