import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `cobranza` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.cobranza` del cloud (`backend-supabase`, migración 0001), con las
/// diferencias de motor de [Ventas]: fechas en epoch ms UTC, sin claves foráneas y sin defaults de
/// servidor. El dinero va en **centavos** (`int`), nunca `double`.
///
/// Esta versión lleva las columnas del cobro en efectivo (HU-COB-001) y los datos opcionales de la
/// tarjeta y de la transferencia (HU-COB-002 y HU-COB-003, #396; migración 0072 del backend) y la
/// marca de anulado con su motivo (HU-COB-006, #422). El servidor cuida que los datos de la tarjeta vayan
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

  /// Cuándo se anuló el cobro, con la hora del teléfono (HU-COB-006, #422; backend 0072 y 0151); `null`
  /// si está vigente. Anular no es dar de baja: [deletedAt] es otra cosa. Va junto con
  /// [motivoAnulacion] y no se reabre.
  IntColumn get anuladoAt => integer().nullable().map(const FechaUtcConverter())();

  /// El motivo de la lista del canvas (el servidor lo cuida con un CHECK; acá lo cuida el caso de uso, que
  /// nunca arma otro, porque SQLite no suma un CHECK de tabla a una tabla que ya existe): `Monto equivocado`, `Cliente equivocado`, `Lo registré dos
  /// veces` u `Otro`. Lo que se escribe con «Otro» no está acá ni sube: queda en el `audit_log` local
  /// («Justificar»).
  TextColumn get motivoAnulacion => text().nullable()();

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
