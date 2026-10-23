import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `house_status` de la DB local cifrada (ADR-003, esquema-datos.md §`house_status`): la cache
/// del color de cada casa en el mapa, **una fila por ubicación**.
///
/// Es la misma tabla que `public.house_status` del cloud (`backend-supabase`, migración 0001, sin la
/// `zona_id` que sacó la 0011): mismas columnas y mismos `CHECK`, incluido el que fija el mapeo 1:1
/// entre `color` y `prioridad`. Las diferencias son las del motor: fechas en epoch ms UTC, sin
/// clave foránea a `ubicacion` y sin defaults de servidor.
///
/// La clave es `ubicacion_id` y no `id`: el contrato lo declara con `SyncSpec.push(…, pk:
/// 'ubicacion_id')`. Sin datos de persona: es lo único del historial de visitas que ve el
/// coordinador (ADR-003, ADR-004).
///
/// La mantiene `HouseStatusUpdaterDrift`, dentro de la transacción de cada escritura que cambia el
/// color (R-UB08); nada la escribe al renderizar el mapa.
@DataClassName('HouseStatusFila')
class HouseStatuses extends Table {
  @override
  String get tableName => 'house_status';

  TextColumn get ubicacionId => text()();

  RealColumn get lat => real()();

  RealColumn get lon => real()();

  /// `CASA`, `NEGOCIO` o `EDIFICIO`.
  TextColumn get tipoUbicacion => text()();

  /// Uno de los siete códigos de `ColorHouseStatus`.
  TextColumn get color => text()();

  /// 1 a 7, el mismo dato que [color].
  IntColumn get prioridad => integer()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: la casa volvió a «Sin visita» (esquema-datos.md §Principios 6).
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {ubicacionId};

  @override
  List<String> get customConstraints => const [
    "CHECK (tipo_ubicacion IN ('CASA', 'NEGOCIO', 'EDIFICIO'))",
    "CHECK (color IN ('ENTREGA_Y_COBRANZA_PENDIENTE', 'COBRANZA_PENDIENTE', "
        "'ENTREVISTA_PROGRAMADA', 'VENTA_COMPLETA', 'ENTREVISTA_SIN_VENTA', 'SIN_CONTESTAR', "
        "'RECHAZO'))",
    'CHECK (prioridad BETWEEN 1 AND 7)',
    // color y prioridad son el mismo dato en dos formas (ADR-003): no pueden contradecirse.
    'CHECK (prioridad = CASE color '
        "WHEN 'ENTREGA_Y_COBRANZA_PENDIENTE' THEN 1 "
        "WHEN 'COBRANZA_PENDIENTE' THEN 2 "
        "WHEN 'ENTREVISTA_PROGRAMADA' THEN 3 "
        "WHEN 'VENTA_COMPLETA' THEN 4 "
        "WHEN 'ENTREVISTA_SIN_VENTA' THEN 5 "
        "WHEN 'SIN_CONTESTAR' THEN 6 "
        "WHEN 'RECHAZO' THEN 7 END)",
  ];
}
