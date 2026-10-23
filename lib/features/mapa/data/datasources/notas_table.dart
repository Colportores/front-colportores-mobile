import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tipos de objeto al que se ata una `nota` (`target_type`, esquema-datos.md §`nota`). Hoy la app
/// escribe `PERSONA` (HU-UBI-008, la primera nota del alta), `VISITA` y `AGENDA` (la nota opcional
/// de cada una, #404); HU-UBI-012 trae el resto.
abstract final class TipoObjetivoNota {
  static const persona = 'PERSONA';
  static const visita = 'VISITA';
  static const agenda = 'AGENDA';
}

/// Tabla `nota` de la DB local cifrada (esquema-datos.md §`nota`): texto libre atado a una persona,
/// una ubicación, una zona, una visita, una agenda o un depto.
///
/// **local-only — PII**: no tiene tabla en el cloud y no entra al sync (`SyncSpec.local`). El texto
/// nunca va a los logs. Sin clave foránea: [targetId] apunta a la tabla que diga [targetType].
@DataClassName('NotaFila')
@TableIndex(name: 'nota_objetivo_idx', columns: {#targetType, #targetId})
class Notas extends Table {
  @override
  String get tableName => 'nota';

  TextColumn get id => text()();

  TextColumn get targetType => text()();

  TextColumn get targetId => text()();

  TextColumn get texto => text()();

  TextColumn get categoria => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
