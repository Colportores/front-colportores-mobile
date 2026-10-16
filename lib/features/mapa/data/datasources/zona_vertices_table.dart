import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `zona_vertice` de la DB local: las esquinas de una zona `ESQUINAS`, en orden. Réplica de
/// solo lectura del canal de catálogo (contrato-sync-engine §2, política `pull`).
///
/// Misma forma que `public.zona_vertice` (backend-supabase 0008) y los mismos `CHECK`, con las
/// diferencias del motor de siempre (ver `Ubicaciones`). **Sin el índice único de `orden` entre las
/// vivas**, por lo mismo que en `zona`: al editar una zona, el delta trae la esquina que se quita
/// (baja) y la que toma su orden, y aplicadas de a una chocarían.
@DataClassName('ZonaVerticeFila')
@TableIndex(name: 'zona_vertice_zona_idx', columns: {#zonaId, #orden})
class ZonaVertices extends Table {
  @override
  String get tableName => 'zona_vertice';

  TextColumn get id => text()();

  TextColumn get zonaId => text()();

  IntColumn get orden => integer()();

  RealColumn get lat => real()();

  RealColumn get lon => real()();

  /// Los nombres de las calles de la esquina, para mostrar. Vacías en las zonas migradas.
  TextColumn get calleA => text().nullable()();

  TextColumn get calleB => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (lat BETWEEN -90 AND 90)',
    'CHECK (lon BETWEEN -180 AND 180)',
  ];
}
