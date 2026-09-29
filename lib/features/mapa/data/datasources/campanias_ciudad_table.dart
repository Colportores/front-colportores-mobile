import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `campania_ciudad` de la DB local: las ciudades de cada campaña (una campaña abarca una o
/// más; las zonas cuelgan de acá). Réplica de solo lectura del canal de catálogo
/// (contrato-sync-engine §2, política `pull`): la app nunca la escribe.
///
/// Misma forma que `public.campania_ciudad` (backend-supabase 0008), con las diferencias del motor
/// de siempre (ver `Ubicaciones`): fechas en epoch ms UTC, sin claves foráneas ni defaults de
/// servidor. **Sin el `UNIQUE (campania_id, ciudad_id)`**: la réplica aplica las filas del delta de a
/// una y el servidor ya lo garantiza; un índice único local podría frenar un delta válido.
@DataClassName('CampaniaCiudadFila')
@TableIndex(name: 'campania_ciudad_ciudad_id_idx', columns: {#ciudadId})
class CampaniasCiudad extends Table {
  @override
  String get tableName => 'campania_ciudad';

  TextColumn get id => text()();

  TextColumn get campaniaId => text()();

  TextColumn get ciudadId => text()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: una ciudad quitada de la campaña deja de abrir sus zonas.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
