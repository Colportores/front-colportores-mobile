import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `venta` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.venta` del cloud (`backend-supabase`, migraciones 0001 y 0071), con
/// las diferencias de motor de [Visitas]: fechas en epoch ms UTC, sin claves foráneas y sin defaults
/// de servidor. El dinero va en **centavos** (`int`), nunca `double`.
///
/// **Sin dato del cliente** (ADR-004): la venta cuelga de `espacio_persona` por un id opaco; el
/// nombre y la dirección de quien compró viven solo en el teléfono (`persona`, `ubicacion`).
///
/// [motivoMontoManual] es la **única excepción** a «ningún texto libre sube» (decisión de Cristian,
/// 23/10, «Monto manual»): lo escribe la colportora cuando cambia el total a mano y lo lee su
/// coordinador, así que la app le avisa antes de guardar. Nunca va a un log.
///
/// «Talonario único por colportor y año» (HU-VEN-001, backend 0071) lo hace cumplir la transacción
/// que escribe la venta, no un índice: el año es el de Montevideo, que SQLite no calcula.
@DataClassName('VentaFila')
@TableIndex(name: 'venta_colportor_idx', columns: {#colportorId, #fecha})
@TableIndex(name: 'venta_espacio_persona_idx', columns: {#espacioPersonaId})
class Ventas extends Table {
  @override
  String get tableName => 'venta';

  TextColumn get id => text()();

  /// El vínculo persona ↔ espacio al que se le vendió.
  TextColumn get espacioPersonaId => text()();

  /// Texto libre: el número impreso en el talonario de papel.
  TextColumn get numeroTalonario => text()();

  /// Lo que se cobra por la venta, en centavos: el calculado o el que la colportora cambió a mano.
  IntColumn get montoTotal => integer()();

  IntColumn get fecha => integer().map(const FechaUtcConverter())();

  TextColumn get colportorId => text()();

  /// La visita que terminó en esta venta; `null` si se registró desde la pestaña Ventas.
  TextColumn get visitaId => text().nullable()();

  /// Por qué la colportora cambió el total a mano; `null` si no lo cambió o no lo explicó.
  TextColumn get motivoMontoManual => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6).
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (monto_total >= 0)'];
}
