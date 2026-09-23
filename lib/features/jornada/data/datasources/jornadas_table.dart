import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `jornada` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.jornada` del cloud (`backend-supabase`, migración 0001) —
/// "modelo único", esquema-datos.md §Principios 1—: mismo nombre, mismas columnas y los mismos
/// `CHECK`. Las diferencias son las del motor:
///
/// - Fechas en epoch ms UTC ([FechaUtcConverter]) en vez de `timestamptz`.
/// - Sin claves foráneas: `usuario` no existe en la DB local.
/// - Sin defaults de servidor (`auth.uid()`, `now()`, `uuid_generate_v7()`): acá los valores los
///   pone siempre la app. Solo quedan los que no dependen de nadie (`total_*` y `sync_version`
///   en 0).
///
/// Los nombres de columna son las claves de `JornadaModel.toJson()` —el payload de sync—; un test
/// fija que coincidan. `acompaniante_id` y `tipo_acompaniamiento` van sin `ñ`, como en el cloud.
///
/// "Una sola jornada activa por colportor" **no** es una restricción de esta tabla: el cloud no
/// la tiene, y un índice único local podría hacer fallar la recuperación de dispositivo.
/// `jornada` es `push` sin `alsoPull` (contrato-sync-engine §2-§3): no baja por pull, así que el
/// único camino por el que entra una jornada del cloud es `engine.recover()`, en la
/// reconciliación desde el watermark del backup (§7, fase 3), donde gana el servidor. Si eso trae
/// una jornada abierta cuando la DB restaurada ya tiene otra, la recuperación no puede fallar por
/// un índice. La regla la sostiene `JornadaLocalDataSourceDrift.insertar`, dentro de una
/// transacción.
@DataClassName('JornadaFila')
@TableIndex(name: 'jornada_colportor_idx', columns: {#colportorId, #inicio})
class Jornadas extends Table {
  @override
  String get tableName => 'jornada';

  /// UUID v7 generado en el dispositivo (esquema-datos.md §Principios 2).
  TextColumn get id => text()();

  TextColumn get colportorId => text()();

  IntColumn get inicio => integer().map(const FechaUtcConverter())();

  /// `NULL` mientras la jornada está en curso.
  IntColumn get fin => integer().nullable().map(const FechaUtcConverter())();

  TextColumn get acompananteId => text().named('acompaniante_id').nullable()();

  TextColumn get tipoAcompanamiento => text().named('tipo_acompaniamiento').nullable()();

  IntColumn get totalVisitas => integer().withDefault(const Constant(0))();

  IntColumn get totalVentas => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  /// Nullable como en el cloud y en `Auditoria.createdBy` (TODO(#8) en `Auditoria`).
  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6).
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (total_visitas >= 0)',
    'CHECK (total_ventas >= 0)',
    'CHECK (fin IS NULL OR fin >= inicio)',
  ];
}
