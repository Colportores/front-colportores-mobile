import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `campania` de la DB local: las campañas, con el nombre y las fechas que la app muestra y con
/// las que decide si una terminó. Réplica de solo lectura del canal de catálogo (contrato-sync-engine
/// §2, política `pull`): la app nunca la escribe.
///
/// Misma forma que `public.campania` (backend-supabase 0001 y 0008: sin `ciudad_id`; las ciudades
/// cuelgan de `campania_ciudad`), con las diferencias del motor de siempre (ver `Ubicaciones`).
/// **Solo las columnas que la app lee hoy**: el servidor manda además `tipo` y `coordinador_id`, y el
/// motor ignora lo que la tabla local no tiene. Desde el esquema 39 se lee también `alquiler_monto`. Las fechas son `date` en el cloud y acá texto
/// `AAAA-MM-DD`, igual que las vigencias de los precios: se comparan como texto y no cambian de día
/// con la zona horaria del teléfono.
@DataClassName('CampaniaFila')
class Campanias extends Table {
  @override
  String get tableName => 'campania';

  TextColumn get id => text()();

  TextColumn get nombre => text()();

  /// Primer día de la campaña, `AAAA-MM-DD`.
  TextColumn get fechaInicio => text()();

  /// Último día de la campaña (inclusive), `AAAA-MM-DD`; `null` = sin fecha de fin (permanente).
  TextColumn get fechaFin => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Lo que cobra la campaña de alquiler a cada colportor inscripto, en **centavos** (backend-supabase
  /// 0067 y 0114, HU-CTA-007, decisión de Cristian 21/10): monto fijo y único por campaña. `null` o 0 =
  /// la campaña no cobra alquiler. Lo cambia el coordinador en el servidor y baja por el pull.
  IntColumn get alquilerMonto => integer().nullable()();

  /// Soft delete: una campaña dada de baja no cuenta como vigente ni por empezar.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
