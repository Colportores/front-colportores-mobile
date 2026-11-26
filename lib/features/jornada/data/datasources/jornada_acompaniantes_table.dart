import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `jornada_acompaniante` de la DB local (esquema-datos.md §jornada_acompaniante, HU-JOR-003):
/// quién acompañó cada jornada, **una fila por (jornada, acompañante)** (decisión de Cristian, 05/11,
/// «Dos acomp.»; backend-supabase 0176, #254). Sube con la jornada (`push`, sin `alsoPull`, como
/// `visita_misionero`) y el teléfono la escribe.
///
/// Misma forma que `public.jornada_acompaniante`, con las diferencias del motor de [Jornadas]. Las columnas
/// que pone el servidor (`colportor_id`, que sale de la jornada, y `cargado_por`, quién la anotó desde el
/// panel) no están acá: el push las descartaría. Una fila no cambia de jornada ni de persona: se da de baja
/// (`deleted_at`) y se suma otra; un solo renglón vivo por (jornada, persona), como el índice del servidor.
@DataClassName('JornadaAcompanianteFila')
@TableIndex(name: 'jornada_acompaniante_jornada_idx', columns: {#jornadaId})
class JornadaAcompaniantes extends Table {
  @override
  String get tableName => 'jornada_acompaniante';

  /// UUID v7 generado en el dispositivo (esquema-datos.md §Principios 2).
  TextColumn get id => text()();

  TextColumn get jornadaId => text()();

  /// La cuenta de quien acompañó: un coordinador de la campaña (la lista del teléfono no ofrece más).
  TextColumn get acompanianteId => text().named('acompaniante_id')();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
