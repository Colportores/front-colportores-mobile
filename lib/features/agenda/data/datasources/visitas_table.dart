import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `visita` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.visita` del cloud (`backend-supabase`, migraciones 0001 y 0069),
/// con las diferencias de motor de [Agendas]: fechas en epoch ms UTC, sin claves foráneas y sin
/// defaults de servidor.
///
/// **Cuelga del espacio** (`espacio_id`, la casa o el depto) y la persona es opcional
/// (`espacio_persona_id` nullable): «No contestó» y «Rechazo» se guardan sin persona (decisión de
/// Cristian del 23/10, «Sin persona»). Sin persona no sube nada de ninguna persona.
///
/// **Sin columna de notas**: las de una visita son filas de `nota` (`target_type = VISITA`,
/// local-only, ADR-017). El `CHECK` de `tipo_resultado` es el del servidor, tal cual (con
/// `COBRANZA`, decisión «Visita cobro»). Las horas de la entrevista (`entrevista_entrada` y
/// `entrevista_salida`) llegan con #466.
@DataClassName('VisitaFila')
@TableIndex(name: 'visita_colportor_idx', columns: {#colportorId, #fecha})
@TableIndex(name: 'visita_espacio_persona_idx', columns: {#espacioPersonaId})
@TableIndex(name: 'visita_espacio_idx', columns: {#espacioId})
class Visitas extends Table {
  @override
  String get tableName => 'visita';

  TextColumn get id => text()();

  /// La casa o el depto de la visita.
  TextColumn get espacioId => text()();

  /// Con quién fue; `null` = sin persona.
  TextColumn get espacioPersonaId => text().nullable()();

  IntColumn get fecha => integer().map(const FechaUtcConverter())();

  /// `VENTA`, `NO_CONTESTO`, `RECHAZO`, `ENTREVISTA` o `COBRANZA`.
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
    "CHECK (tipo_resultado IN ('VENTA', 'NO_CONTESTO', 'RECHAZO', 'ENTREVISTA', 'COBRANZA'))",
  ];
}
