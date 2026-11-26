import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `cuenta_colportor` de la DB local (esquema-datos.md §cuenta_colportor, HU-CTA-002): la cuenta
/// de la colportora con su deuda con la casa editora. Réplica de **solo lectura** (contrato-sync-engine
/// §2, política `pull`, backend-supabase 0179, #254): la escribe el servidor al autorizar un pedido,
/// validar un depósito o un cobro con tarjeta, trasladar un alquiler pagado de más, etc., y el teléfono
/// no la sube ni la cambia. Es lo que le deja calcular la deuda y verla sin conexión (decisión de
/// Cristian, 05/11, «nada de consultas a cada rato»).
///
/// Misma forma que `public.cuenta_colportor` (0119, 0152), con las diferencias del motor de siempre
/// (ver `Stocks`): fechas en epoch ms UTC, sin claves foráneas ni defaults de servidor y sin el `UNIQUE`
/// de `usuario_id` (el servidor ya lo garantiza y un índice único local podría frenar un delta válido).
/// El dinero va en **centavos** (`int`); `deuda_total` puede ser negativa (a favor, «Pago de más»).
/// `usuario_id` es siempre el de la propia colportora (el pull baja solo las filas del dueño).
@DataClassName('CuentaColportorFila')
@TableIndex(name: 'cuenta_colportor_usuario_idx', columns: {#usuarioId})
class CuentasColportor extends Table {
  @override
  String get tableName => 'cuenta_colportor';

  TextColumn get id => text()();

  /// La colportora dueña de la cuenta.
  TextColumn get usuarioId => text()();

  /// La deuda real con la casa editora (centavos): la que movió cualquier causa. Una cuenta dada de baja
  /// (`deleted_at`) no debe nada.
  IntColumn get deudaTotal => integer().withDefault(const Constant(0))();

  IntColumn get dineroDepositado => integer().withDefault(const Constant(0))();

  IntColumn get dineroEnMano => integer().withDefault(const Constant(0))();

  IntColumn get dineroPorCobrar => integer().withDefault(const Constant(0))();

  /// Sin uso desde el 25/10 («Alq. campaña»): el alquiler se lleva por campaña.
  IntColumn get deudaAlquiler => integer().withDefault(const Constant(0))();

  /// El total del alquiler pagado de más que pasó a la deuda con la casa editora (0152).
  IntColumn get alquilerTrasladado => integer().withDefault(const Constant(0))();

  IntColumn get actualizadoEn => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: una cuenta dada de baja deja de contar, pero el delta la trae como tombstone para que
  /// el teléfono no conserve una deuda vieja.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
