import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';
import 'geojson_converter.dart';

/// Tabla `zona` de la DB local: las zonas dibujadas sobre el mapa de cada ciudad de una campaña.
/// Réplica de solo lectura del canal de catálogo (contrato-sync-engine §2, política `pull`).
///
/// Misma forma que `public.zona` después de backend-supabase 0008 (cuelga de `campania_ciudad`,
/// sin `ciudad_id` ni `campania_id`) y los mismos `CHECK`, con las diferencias del motor de siempre
/// (ver `Ubicaciones`). `poligono_geojson` es el `jsonb` del cloud guardado como texto; el color
/// hexadecimal se valida con `GLOB` porque SQLite no trae expresiones regulares. **Sin el índice
/// único de nombre por ciudad**: la réplica aplica las filas del delta de a una y renombrar dos
/// zonas entre sí chocaría a mitad de camino; el servidor ya lo garantiza.
@DataClassName('ZonaFila')
@TableIndex(name: 'zona_campania_ciudad_idx', columns: {#campaniaCiudadId})
class Zonas extends Table {
  @override
  String get tableName => 'zona';

  TextColumn get id => text()();

  TextColumn get nombre => text()();

  TextColumn get campaniaCiudadId => text()();

  /// `RADIAL` (un círculo: centro y radio) o `ESQUINAS` (el recorrido por calles entre sus
  /// `zona_vertice`).
  TextColumn get tipoForma => text()();

  RealColumn get centroLat => real().nullable()();

  RealColumn get centroLon => real().nullable()();

  /// Solo `RADIAL`, en metros.
  IntColumn get radioM => integer().nullable()();

  /// `Polygon` GeoJSON en `[lon, lat]`: lo que se dibuja y con lo que se ubica cada dirección.
  TextColumn get poligonoGeojson => text().map(const GeojsonConverter())();

  /// `#RRGGBB`, o `null`.
  TextColumn get color => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: una zona dada de baja no cubre ningún punto.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (tipo_forma IN ('RADIAL', 'ESQUINAS'))",
    "CHECK (tipo_forma <> 'RADIAL' OR "
        '(centro_lat IS NOT NULL AND centro_lon IS NOT NULL AND radio_m IS NOT NULL))',
    'CHECK (radio_m IS NULL OR radio_m BETWEEN 1 AND 3000)',
    'CHECK ((centro_lat IS NULL OR centro_lat BETWEEN -90 AND 90) AND '
        '(centro_lon IS NULL OR centro_lon BETWEEN -180 AND 180))',
    "CHECK (color IS NULL OR color GLOB '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]"
        "[0-9A-Fa-f][0-9A-Fa-f]')",
  ];
}
