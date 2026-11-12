import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `espacio_persona` de la DB local cifrada (esquema-datos.md §Modelo de Espacio, ADR-001):
/// el vínculo entre una persona y un espacio (M:N).
///
/// Misma tabla que `public.espacio_persona` del cloud (`backend-supabase`, migración 0001): **sube**
/// por `push`, sin `alsoPull`, y solo con IDs opacos (ADR-017). `persona_id` no es clave foránea: la
/// tabla `persona` no existe en el cloud y, tras una recuperación sin backup, el vínculo puede volver
/// sin su persona. Tampoco la hay a `espacio` ni a `ubicacion`: el pull no garantiza el orden.
@DataClassName('EspacioPersonaFila')
@TableIndex(name: 'espacio_persona_espacio_idx', columns: {#espacioId})
@TableIndex(name: 'espacio_persona_persona_idx', columns: {#personaId})
class EspacioPersonas extends Table {
  @override
  String get tableName => 'espacio_persona';

  TextColumn get id => text()();

  TextColumn get espacioId => text()();

  TextColumn get personaId => text()();

  TextColumn get ubicacionCobranzaAltId => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
