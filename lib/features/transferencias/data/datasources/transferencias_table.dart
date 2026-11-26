import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `transferencia_stock` de la DB local cifrada (esquema-datos.md §transferencia_stock,
/// HU-STK-005, backend-supabase 0067, 0126, 0127, 0139 y 0148).
///
/// Es la misma tabla que `public.transferencia_stock` del cloud, con las diferencias de motor de
/// siempre (ver [Depositos]): fechas en epoch ms UTC, sin claves foráneas y sin defaults de servidor.
///
/// Sube por el motor (`push`, con `alsoPull`): el colportor la pide y la cancela desde el teléfono, y
/// baja a las **dos puntas** con su estado (backend 0148, «Ver transf.»), la arme quien la arme. Las
/// columnas que pone **solo el servidor** están acá porque bajan con el pull y de ellas sale lo que
/// la pantalla muestra: `solicitante_id` (quién la pidió desde el teléfono; `null` en la que arma el
/// coordinador), `fecha_solicitud` (cuándo LLEGÓ al servidor: mientras es `null` la transferencia sigue
/// «En cola» en este teléfono), `numero`, `decidido_en` y `motivo_rechazo`. El push las descarta y el
/// modelo no las manda. `coordinador_id`, `monto_deuda`, `baja_a_1` y `baja_a_2` bajan pero no se
/// guardan: ninguna pantalla las usa.
///
/// `origen_id` es quien **da** los materiales y `destino_id` quien los **recibe**: el colportor que
/// pide desde el teléfono es siempre el destino.
///
/// **Sin dato de ninguna persona más que ids opacos** (ADR-004): no hay nombres, solo ids de usuario.
@DataClassName('TransferenciaStockFila')
@TableIndex(name: 'transferencia_stock_origen_idx', columns: {#origenId})
@TableIndex(name: 'transferencia_stock_destino_idx', columns: {#destinoId})
class TransferenciasStock extends Table {
  @override
  String get tableName => 'transferencia_stock';

  TextColumn get id => text()();

  /// Quien da los materiales.
  TextColumn get origenId => text()();

  /// Quien los recibe.
  TextColumn get destinoId => text()();

  /// `PENDIENTE_AUTORIZACION`, `AUTORIZADO`, `EJECUTADO`, `RECHAZADO` o `CANCELADO`.
  TextColumn get estado => text().withDefault(const Constant('PENDIENTE_AUTORIZACION'))();

  /// Quién la pidió desde el teléfono (`origen_id` o `destino_id`). La pone el servidor; `null` en la
  /// que arma el coordinador y en la que todavía no subió.
  TextColumn get solicitanteId => text().nullable()();

  /// Cuándo llegó al servidor, con su reloj. `null` hasta que sube: la transferencia está «En cola».
  IntColumn get fechaSolicitud => integer().nullable().map(const FechaUtcConverter())();

  /// El número visible («T-18», backend 0127). Lo pone el servidor.
  IntColumn get numero => integer().nullable()();

  /// Cuándo la autorizó o la rechazó el coordinador.
  IntColumn get decididoEn => integer().nullable().map(const FechaUtcConverter())();

  /// Por qué la rechazó el coordinador (hasta 500 caracteres). Es texto libre: nunca va a un log.
  TextColumn get motivoRechazo => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete. Desde el teléfono no se da de baja una transferencia: se cancela.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (estado IN ('PENDIENTE_AUTORIZACION', 'AUTORIZADO', 'EJECUTADO', 'RECHAZADO', "
        "'CANCELADO'))",
    'CHECK (origen_id <> destino_id)',
  ];
}

/// Tabla `transferencia_item` de la DB local: una línea de la transferencia, un producto y cuántas
/// unidades pasan de `origen_id` a `destino_id` (backend-supabase 0067 y 0139).
///
/// Sube después de su encabezado y baja con él (`alsoPull`). `precio_unitario` (la foto del costo al
/// autorizar), `solicitante_id` y `baja_a_*` los pone el servidor y no se guardan: la transferencia
/// mueve materiales, no plata (vista 40: «sin precios»).
@DataClassName('TransferenciaItemFila')
@TableIndex(name: 'transferencia_item_transferencia_idx', columns: {#transferenciaId})
class TransferenciaItems extends Table {
  @override
  String get tableName => 'transferencia_item';

  TextColumn get id => text()();

  TextColumn get transferenciaId => text()();

  TextColumn get productoId => text()();

  /// Unidades; siempre mayor que cero.
  IntColumn get cantidad => integer()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (cantidad > 0)'];
}
