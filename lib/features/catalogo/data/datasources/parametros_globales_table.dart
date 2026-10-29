import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `parametro_global` de la DB local: los parámetros de toda la aplicación que cambia
/// Administración (backend-supabase 0070). Hoy uno solo: `dias_antiguedad_precios`, los días desde que
/// el teléfono bajó los precios a partir de los cuales el aviso de Precios se pone fuerte (decisión de
/// Cristian, 23/10, «Precio viejo»). Réplica de solo lectura del canal de catálogo (contrato-sync-engine
/// §2, política `pull`, sin filtro: el valor es el mismo para todos): la app nunca la escribe.
///
/// Misma forma que `public.parametro_global`, con las diferencias del motor de siempre (ver
/// `Ubicaciones`): fechas en epoch ms UTC y sin claves foráneas. **Sin el `CHECK` de `clave`** (el
/// servidor lo ensancha con cada parámetro nuevo; un teléfono con la app vieja no puede frenar el pull
/// por una clave que todavía no entiende) **ni el índice de «una sola fila viva por clave»** (la
/// réplica aplica las filas de a una y el servidor ya lo garantiza).
@DataClassName('ParametroGlobalFila')
class ParametrosGlobales extends Table {
  @override
  String get tableName => 'parametro_global';

  TextColumn get id => text()();

  /// Nombre del parámetro (hoy `dias_antiguedad_precios`).
  TextColumn get clave => text()();

  /// Valor entero. Para `dias_antiguedad_precios`: días, 1 o más.
  IntColumn get valor => integer()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: un parámetro dado de baja deja de regir y vuelve su valor por defecto.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
