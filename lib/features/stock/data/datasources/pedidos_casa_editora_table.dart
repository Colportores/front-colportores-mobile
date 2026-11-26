import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `pedido_casa_editora` de la DB local (esquema-datos.md §pedido_casa_editora): el pedido de libros
/// de la colportora a la casa editora. Es una entidad `push` **con pull de lo propio** (contrato-sync-engine
/// §2, `alsoPull`, backend-supabase 0124): el pedido se va a armar sin conexión desde la pantalla de pedidos
/// (HU-STK-009, #387) y la colportora ve cómo sigue con lo que baja del servidor. Hasta que esa pantalla
/// exista, la tabla solo recibe lo que baja: la usa la deuda con la casa editora (HU-CTA-002, #671), que
/// reparte lo pagado entre los pedidos AUTORIZADO, DESPACHADO y RECIBIDO, el más viejo primero.
///
/// Misma forma que `public.pedido_casa_editora` (0124, 0112, 0130), con las diferencias del motor de
/// siempre (ver `Stocks`): fechas en epoch ms UTC, sin claves foráneas, sin defaults de servidor y sin el
/// `UNIQUE` de `numero` (el servidor ya lo garantiza). El dinero va en **centavos** (`int`).
///
/// Lo que pone el servidor y el push descarta: `coordinador_id`, `fecha_pedido` (cuándo **llegó**), `origen`,
/// `monto_total`, `excede_limite`, `monto_autorizado`, `decidido_por`, `decidido_en`, `motivo_rechazo` y
/// `numero`. `estado` es del push en el alta (`PENDIENTE_AUTORIZACION`) y en la cancelación (`CANCELADO`).
@DataClassName('PedidoCasaEditoraFila')
@TableIndex(name: 'pedido_casa_editora_colportor_idx', columns: {#colportorId})
class PedidosCasaEditora extends Table {
  @override
  String get tableName => 'pedido_casa_editora';

  TextColumn get id => text()();

  /// La colportora dueña del pedido.
  TextColumn get colportorId => text()();

  /// Quien lo registró, si fue el coordinador a nombre de la colportora (`origen = COORDINADOR`).
  TextColumn get coordinadorId => text().nullable()();

  /// Cuándo llegó el pedido al servidor.
  IntColumn get fechaPedido => integer().map(const FechaUtcConverter())();

  /// `BORRADOR`, `PENDIENTE_AUTORIZACION`, `AUTORIZADO`, `DESPACHADO`, `RECIBIDO`, `RECHAZADO` o `CANCELADO`.
  TextColumn get estado => text()();

  /// Lo que pidió la colportora: la suma de cantidad por precio de sus líneas (centavos).
  IntColumn get montoTotal => integer().withDefault(const Constant(0))();

  /// `COLPORTOR` o `COORDINADOR`.
  TextColumn get origen => text().withDefault(const Constant('COLPORTOR'))();

  BoolColumn get excedeLimite => boolean().withDefault(const Constant(false))();

  /// Lo que autorizó el coordinador (centavos); `null` = todavía no se decidió. Es lo que se cargó a la deuda.
  IntColumn get montoAutorizado => integer().nullable()();

  TextColumn get decididoPor => text().nullable()();

  IntColumn get decididoEn => integer().nullable().map(const FechaUtcConverter())();

  TextColumn get motivoRechazo => text().nullable()();

  /// El «Pedido #231»: sale de una secuencia global del servidor.
  IntColumn get numero => integer().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
