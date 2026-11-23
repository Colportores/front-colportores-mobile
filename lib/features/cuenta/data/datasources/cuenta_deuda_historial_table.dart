import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `cuenta_deuda_historial` de la DB local (esquema-datos.md §cuenta_deuda_historial, HU-CTA-001):
/// la deuda con la casa editora de la colportora a lo largo del tiempo, una fila por cada cambio de
/// `cuenta_colportor.deuda_total` con la hora en que cambió (backend-supabase 0168). Réplica de **solo
/// lectura** (política `pull`, 0179, #254): la llena el servidor y el teléfono no la escribe. De ahí sale
/// la deuda de hace 7 días: la de la última fila con [desde] igual o anterior a «ahora − 7 días»
/// (decisión de Cristian, 04/11, «Variación semanal»).
///
/// Misma forma que `public.cuenta_deuda_historial`, con las diferencias del motor de siempre (ver
/// `Stocks`): fechas en epoch ms UTC, sin claves foráneas ni defaults de servidor. [deuda] va en
/// **centavos** y puede ser negativa (a favor).
@DataClassName('CuentaDeudaHistorialFila')
@TableIndex(name: 'cuenta_deuda_historial_usuario_idx', columns: {#usuarioId, #desde})
class CuentaDeudaHistoriales extends Table {
  @override
  String get tableName => 'cuenta_deuda_historial';

  TextColumn get id => text()();

  /// La colportora dueña de la cuenta.
  TextColumn get usuarioId => text()();

  /// La deuda real desde [desde] (centavos; negativa = a favor).
  IntColumn get deuda => integer()();

  /// Desde cuándo vale esa deuda (hasta la fila siguiente de la misma persona).
  IntColumn get desde => integer().map(const FechaUtcConverter())();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
