import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `pais` de la DB local: el catálogo de países del Admin (V1: solo Uruguay; `ciudad.pais_id`
/// apunta acá en el servidor). Réplica de solo lectura del canal de catálogo (contrato-sync-engine
/// §2, política `pull`): la app nunca la escribe. Se replica porque el contrato la lista entre las
/// entidades `pull` (decisión del 12/11 sobre P1 de #181); hoy ninguna pantalla la lee.
///
/// Misma forma que `public.pais` (backend-supabase 0001), con las diferencias del motor de siempre
/// (ver `Ciudades`): fechas en epoch ms UTC, sin claves foráneas ni defaults de servidor.
@DataClassName('PaisFila')
class Paises extends Table {
  @override
  String get tableName => 'pais';

  TextColumn get id => text()();

  TextColumn get nombre => text()();

  /// Código ISO 3166-1 alfa-2 («UY»).
  TextColumn get isoCode => text()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete, como el resto del catálogo.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
