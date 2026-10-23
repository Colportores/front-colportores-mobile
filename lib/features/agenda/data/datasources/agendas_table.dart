import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `agenda` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.agenda` del cloud (`backend-supabase`, migración 0001) —"modelo
/// único", esquema-datos.md §Principios 1—: mismo nombre, mismas columnas y los mismos `CHECK`. Las
/// diferencias son las del motor, igual que en `jornada` y `ubicacion`:
///
/// - Fechas en epoch ms UTC ([FechaUtcConverter]) en vez de `timestamptz`.
/// - Sin claves foráneas: `espacio_persona`, `ubicacion` y `visita` pueden llegar al teléfono en
///   cualquier orden (pull, recuperación) y el servidor es quien las valida.
/// - Sin defaults de servidor (`auth.uid()`, `now()`, `uuid_generate_v7()`): los pone siempre la app.
///
/// **Sin columna de notas**: las de una agenda son filas de `nota` (`target_type = AGENDA`,
/// local-only, ADR-017). Por eso la fila entera sube: nada de lo que hay acá es personal.
///
/// Los nombres de columna son las claves de `AgendaModel.toJson()` —el payload de sync—; un test
/// fija que coincidan. Los `CHECK` de `tipo` y `estado` son los del servidor, tal cual (pendiente
/// P1 de #151: la HU habla de otros nombres de estado).
@DataClassName('AgendaFila')
@TableIndex(name: 'agenda_colportor_idx', columns: {#colportorId, #fechaProgramada})
@TableIndex(name: 'agenda_espacio_persona_idx', columns: {#espacioPersonaId})
class Agendas extends Table {
  @override
  String get tableName => 'agenda';

  /// UUID v7 generado en el dispositivo (esquema-datos.md §Principios 2).
  TextColumn get id => text()();

  TextColumn get espacioPersonaId => text()();

  /// `ENTREVISTA` o `COBRANZA`.
  TextColumn get tipo => text()();

  IntColumn get fechaProgramada => integer().map(const FechaUtcConverter())();

  TextColumn get slotCodigo => text().nullable()();

  BoolColumn get esEstricta => boolean().withDefault(const Constant(false))();

  TextColumn get ubicacionAltId => text().nullable()();

  /// `PENDIENTE`, `COMPLETADA` o `CANCELADA`.
  TextColumn get estado => text().withDefault(const Constant('PENDIENTE'))();

  TextColumn get colportorId => text()();

  /// Se completa al registrar la visita que cumple la agenda.
  TextColumn get visitaId => text().nullable()();

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
    "CHECK (tipo IN ('ENTREVISTA', 'COBRANZA'))",
    "CHECK (estado IN ('PENDIENTE', 'COMPLETADA', 'CANCELADA'))",
  ];
}
