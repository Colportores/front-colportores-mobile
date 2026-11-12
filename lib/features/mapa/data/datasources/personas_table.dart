import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `persona` de la DB local cifrada (esquema-datos.md §Modelo de Espacio, HU-UBI-008): el
/// cliente del colportor.
///
/// **local-only — PII (Ley 18.331)**: no tiene tabla en el cloud y no entra al sync (`SyncSpec.local`
/// en `catalogo.dart`). Nunca va a los logs. Lleva las columnas de auditoría de toda fila, pero
/// `sync_version` queda en 0 para siempre. Sin clave foránea a nada: el vínculo con el espacio vive en
/// [EspacioPersonas].
@DataClassName('PersonaFila')
class Personas extends Table {
  @override
  String get tableName => 'persona';

  TextColumn get id => text()();

  TextColumn get nombre => text()();

  /// Vacío si la persona no tiene apellido (la entidad `Persona` lo pide no nulo).
  TextColumn get apellido => text().withDefault(const Constant(''))();

  TextColumn get telefono => text().nullable()();

  /// Del esquema (`notas_globales`). Las notas de una persona son filas de `nota`; esta columna no se
  /// escribe.
  TextColumn get notasGlobales => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
