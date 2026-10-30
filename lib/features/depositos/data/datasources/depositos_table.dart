import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `deposito` de la DB local cifrada (esquema-datos.md §deposito, HU-CTA-004).
///
/// Es la misma tabla que `public.deposito` del cloud (`backend-supabase`, migraciones 0067, 0114 y
/// 0122), con las diferencias de motor de [Cobranzas]: fechas en epoch ms UTC, sin claves foráneas y
/// sin defaults de servidor. El dinero va en **centavos** (`int`), nunca `double`.
///
/// Las columnas que pone el servidor no están acá, porque el push las descarta y todavía no bajan al
/// teléfono (contrato §2): `colportor_id` (sale del JWT; en el teléfono es el `created_by`),
/// `validado_en` y `validado_por` (al validar el coordinador, HU-COB-008) y `rechazado_en`,
/// `rechazado_por` y `motivo_rechazo` (al rechazar un retiro, 0152).
///
/// Los CHECK repiten los del servidor: un depósito que el servidor rechazaría con `23514` no entra ni
/// en el teléfono. El caso de uso nunca arma otra cosa.
///
/// **Sin dato de ninguna persona** (ADR-004): no hay cobros ni clientes en la fila.
@DataClassName('DepositoFila')
@TableIndex(name: 'deposito_ticket_idx', columns: {#ticketId})
class Depositos extends Table {
  @override
  String get tableName => 'deposito';

  TextColumn get id => text()();

  /// Lo depositado, en centavos; siempre mayor que cero.
  IntColumn get monto => integer()();

  /// Cuándo se depositó.
  IntColumn get fecha => integer().map(const FechaUtcConverter())();

  /// `BANCO`, `OFICINA` o `RETIRO_COORDINADOR`.
  TextColumn get destino => text()();

  /// `CASA_EDITORA` o `ALQUILER`.
  TextColumn get concepto => text()();

  /// La campaña a la que paga; obligatoria con `ALQUILER`.
  TextColumn get campaniaId => text().nullable()();

  /// El ticket del banco; obligatorio con `BANCO` y `OFICINA`, ausente con `RETIRO_COORDINADOR`.
  TextColumn get ticketId => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6). Desde el teléfono no se da de baja un depósito.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (monto > 0)',
    "CHECK (destino IN ('BANCO', 'OFICINA', 'RETIRO_COORDINADOR'))",
    "CHECK (concepto IN ('CASA_EDITORA', 'ALQUILER'))",
    "CHECK (destino <> 'RETIRO_COORDINADOR' OR ticket_id IS NULL)",
    "CHECK (destino = 'RETIRO_COORDINADOR' OR ticket_id IS NOT NULL)",
    "CHECK (concepto <> 'ALQUILER' OR campania_id IS NOT NULL)",
  ];
}
