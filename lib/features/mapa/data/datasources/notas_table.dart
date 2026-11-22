import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tipos de objeto al que se ata una `nota` (`target_type`, esquema-datos.md §`nota`). Hoy la app
/// escribe `PERSONA` (HU-UBI-008, la primera nota del alta, y las notas de la ficha, HU-UBI-012),
/// `VISITA` y `AGENDA` (la nota opcional de cada una, #404) y `UBICACION` (las notas del lugar de la
/// pestaña Notas de la hoja de la casa, vista 39, #447: varias por lugar, cada una con su fecha). Las
/// de un depto (`ESPACIO`) esperan el diseño de la vista 11 (#290).
abstract final class TipoObjetivoNota {
  static const persona = 'PERSONA';
  static const ubicacion = 'UBICACION';
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
