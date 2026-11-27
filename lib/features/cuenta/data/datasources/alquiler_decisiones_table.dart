import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `alquiler_decision` de la DB local: lo que el coordinador (o un ADMIN) decidió hacer con lo
/// pagado de alquiler por quien se dio de baja de una campaña (HU-CTA-007, «Mi alquiler»). Réplica de
/// **solo lectura**, de solo bajada (contrato-sync-engine §2, política `pull`): la app nunca la escribe,
/// la escribe únicamente `decidir_alquiler_pagado()` del servidor. El pull baja solo las decisiones de
/// quien sincroniza (`sync.entidad.columna_duenio = usuario_id`, backend-supabase 0201, #301), así que
/// `usuario_id` es siempre el de esta sesión.
///
/// Misma forma que `public.alquiler_decision` (backend-supabase 0159 y 0167), con las diferencias del
/// motor de siempre (ver `Ubicaciones`): fechas en epoch ms UTC y sin claves foráneas. **Sin texto
/// libre** (ninguna columna lo admite) y **sin `decidido_por`**: quién decidió no hace falta para decir
/// qué se decidió, y no se guarda de más.
///
/// La decisión es un paso que se **suma**: una por todo lo pagado hasta ese momento (`monto`, en
/// centavos). Una decisión deshecha (la persona volvió a la campaña: «a cuenta» y «se lo queda» ya no
/// cuentan) baja como baja lógica (`deleted_at`); «devolver» no se deshace, la plata ya volvió.
@DataClassName('AlquilerDecisionFila')
@TableIndex(name: 'alquiler_decision_usuario_campania_idx', columns: {#usuarioId, #campaniaId})
class AlquilerDecisiones extends Table {
  @override
  String get tableName => 'alquiler_decision';

  TextColumn get id => text()();

  /// La persona que pagó, dueña de la fila: la de esta sesión.
  TextColumn get usuarioId => text()();

  TextColumn get campaniaId => text()();

  /// `DEVOLVER_AL_COLPORTOR`, `A_CUENTA_PROXIMO_DEPOSITO` o `SE_LO_QUEDA_EL_COORDINADOR`
  /// (backend-supabase 0167). Se guarda el código del servidor, sin traducir: un valor que esta versión
  /// de la app no conoce se ignora al leer, nunca se inventa un destino.
  TextColumn get decision => text()();

  /// Lo decidido en ese paso, en centavos (mayor que 0).
  IntColumn get monto => integer()();

  /// Cuándo empezó la transacción de la decisión. Para saber qué pagos son de después de la última
  /// decisión se usa [createdAt], no esta (la hora real de la decisión, 0181).
  IntColumn get decididoEn => integer().map(const FechaUtcConverter())();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: una decisión deshecha deja de contar, pero el delta la trae como tombstone para que
  /// el teléfono no siga mostrando un destino que ya no vale.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
