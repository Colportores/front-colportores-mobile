import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `visita` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.visita` del cloud (`backend-supabase`, migración 0001), con las
/// diferencias de motor de [Agendas]: fechas en epoch ms UTC, sin claves foráneas y sin defaults de
/// servidor.
///
/// **Sin columna de notas**: las de una visita son filas de `nota` (`target_type = VISITA`,
/// local-only, ADR-017). El `CHECK` de `tipo_resultado` es el del servidor, tal cual: sin
/// `COBRANZA` (pendiente P2 de #151).
@DataClassName('VisitaFila')
@TableIndex(name: 'visita_colportor_idx', columns: {#colportorId, #fecha})
@TableIndex(name: 'visita_espacio_persona_idx', columns: {#espacioPersonaId})
class Visitas extends Table {
  @override
  String get tableName => 'visita';

  TextColumn get id => text()();

  TextColumn get espacioPersonaId => text()();

  IntColumn get fecha => integer().map(const FechaUtcConverter())();

  /// `VENTA`, `NO_CONTESTO`, `RECHAZO` o `ENTREVISTA`.
  TextColumn get tipoResultado => text()();

  TextColumn get colportorId => text()();

  TextColumn get jornadaId => text().nullable()();

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
    "CHECK (tipo_resultado IN ('VENTA', 'NO_CONTESTO', 'RECHAZO', 'ENTREVISTA'))",
  ];
}
