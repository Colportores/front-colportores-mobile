import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `cobranza` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.cobranza` del cloud (`backend-supabase`, migración 0001), con las
/// diferencias de motor de [Ventas]: fechas en epoch ms UTC, sin claves foráneas y sin defaults de
/// servidor. El dinero va en **centavos** (`int`), nunca `double`.
///
/// Esta versión lleva las columnas del cobro en efectivo (HU-COB-001) y los datos opcionales de la
/// tarjeta y de la transferencia (HU-COB-002 y HU-COB-003, #396; migración 0072 del backend). La
/// anulación (#422) suma sus columnas con su HU. El servidor cuida que los datos de la tarjeta vayan
/// solo en un cobro con TARJETA y los de la transferencia solo en uno con TRANSFERENCIA; acá lo cuida
/// el caso de uso, que nunca arma otra cosa.
///
/// **Sin dato del cliente** (ADR-004, R-CB03): la cobranza cuelga de la venta por un id opaco.
@DataClassName('CobranzaFila')
@TableIndex(name: 'cobranza_venta_idx', columns: {#ventaId})
class Cobranzas extends Table {
  @override
  String get tableName => 'cobranza';

  TextColumn get id => text()();

  /// La venta que se cobra.
  TextColumn get ventaId => text()();

  /// Lo cobrado, en centavos; siempre mayor que cero.
  IntColumn get monto => integer()();

  /// `EFECTIVO`, `TARJETA` o `TRANSFERENCIA`.
  TextColumn get medio => text()();

  /// Cuándo pagó el cliente (`fecha_pago`).
  IntColumn get fecha => integer().map(const FechaUtcConverter())();

  /// Número de cuota (HU-COB-004); `null` si el cobro no es de una cuota.
  IntColumn get numeroCuota => integer().nullable()();

  /// `DEBITO` o `CREDITO`; solo con TARJETA. Opcional.
  TextColumn get tarjetaTipo => text().nullable()();

  /// La marca de la tarjeta, 1 a 40 caracteres; solo con TARJETA. Opcional.
  TextColumn get tarjetaMarca => text().nullable()();

  /// El número de aprobación del ticket, 1 a 40 caracteres; solo con TARJETA. Opcional.
  TextColumn get numeroAprobacion => text().nullable()();

  /// El número de operación de la transferencia, 1 a 40 caracteres; solo con TRANSFERENCIA. Opcional.
  TextColumn get referenciaTransferencia => text().nullable()();

  /// El banco de origen, como texto de 1 a 60 caracteres; solo con TRANSFERENCIA. Opcional.
  TextColumn get bancoOrigen => text().nullable()();

  /// El ticket del cobro con tarjeta (HU-COB-007, #426): el id de una fila de `ticket`. Opcional; se
  /// completa cuando el colportor carga el ticket. Es un id opaco, sin dato del cliente.
  TextColumn get ticketId => text().nullable()();

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
    'CHECK (monto > 0)',
    "CHECK (medio IN ('EFECTIVO','TARJETA','TRANSFERENCIA'))",
  ];
}
