import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `ubicacion` de la DB local cifrada (esquema-datos.md §Modelo de Espacio).
///
/// Es la misma tabla que `public.ubicacion` del cloud (`backend-supabase`, migración 0001) —
/// "modelo único", esquema-datos.md §Principios 1—: mismo nombre, mismas columnas y los mismos
/// `CHECK`. Las diferencias son las del motor, igual que en `jornada`:
///
/// - Fechas en epoch ms UTC ([FechaUtcConverter]) en vez de `timestamptz`.
/// - Sin claves foráneas: `ciudad`, `zona` y `usuario` no existen todavía en la DB local.
/// - Sin defaults de servidor: el `id` y las fechas los pone siempre la app.
///
/// Los nombres de columna son las claves de `UbicacionModel.toJson()` —el payload de sync, que
/// sube la fila entera (ADR-004)—; un test fija que coincidan.
///
/// **No hay índice único** sobre `(ciudad_id, calle, numero)`: RF-UB08 es una advertencia que
/// permite "crear igual con justificación" (ADR-004). El índice `(ciudad_id, lat)` acelera la
/// búsqueda de candidatas a duplicado del alta, que filtra por ciudad y por un recuadro alrededor
/// del punto.
@DataClassName('UbicacionFila')
@TableIndex(name: 'ubicacion_ciudad_idx', columns: {#ciudadId, #lat})
class Ubicaciones extends Table {
  @override
  String get tableName => 'ubicacion';

  /// UUID v7 generado en el dispositivo (esquema-datos.md §Principios 2).
  TextColumn get id => text()();

  /// `CASA`, `NEGOCIO` o `EDIFICIO`, los valores del cloud.
  TextColumn get tipo => text()();

  /// Nullable: el alta por marcador manual puede no conocerla (R-UB02).
  TextColumn get calle => text().nullable()();

  TextColumn get numero => text().nullable()();

  RealColumn get lat => real()();

  RealColumn get lon => real()();

  TextColumn get ciudadId => text()();

  /// Server-authoritative en el cloud: el alta la deja en `NULL`.
  TextColumn get zonaId => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6).
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (tipo IN ('CASA', 'NEGOCIO', 'EDIFICIO'))",
    'CHECK (lat BETWEEN -90 AND 90)',
    'CHECK (lon BETWEEN -180 AND 180)',
  ];
}
