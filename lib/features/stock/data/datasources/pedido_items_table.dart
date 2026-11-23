import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `pedido_item` de la DB local (esquema-datos.md §pedido_item): una línea de un pedido a la casa
/// editora. Igual que [PedidosCasaEditora] es `push` **con pull de lo propio** (contrato-sync-engine §2,
/// `alsoPull`, backend-supabase 0124): por ahora solo recibe lo que baja y la usa la deuda con la casa
/// editora (HU-CTA-002, #671) para decir qué libros trae cada pedido con saldo.
///
/// Misma forma que `public.pedido_item` (0124, 0112), con las diferencias del motor de siempre (ver
/// `Stocks`): fechas en epoch ms UTC, sin claves foráneas ni defaults de servidor y sin el `UNIQUE
/// (pedido_id, producto_id)`. Lo que pone el servidor y el push descarta: `colportor_id`, `precio_unitario`
/// (la foto de `producto.precio_base_compra`, centavos), `cantidad_recibida` y `cantidad_autorizada`
/// (`null` = se autorizó lo pedido).
@DataClassName('PedidoItemFila')
@TableIndex(name: 'pedido_item_pedido_idx', columns: {#pedidoId})
class PedidoItems extends Table {
  @override
  String get tableName => 'pedido_item';

  TextColumn get id => text()();

  TextColumn get pedidoId => text()();

  TextColumn get productoId => text()();

  /// Lo que pidió la colportora (mayor que 0).
  IntColumn get cantidad => integer()();

  /// El costo de la casa editora al pedir (centavos).
  IntColumn get precioUnitario => integer().nullable()();

  IntColumn get cantidadRecibida => integer().nullable()();

  /// La colportora dueña del pedido (la copia el servidor del pedido).
  TextColumn get colportorId => text().nullable()();

  /// Lo que autorizó el coordinador de la línea cuando redujo el pedido; `null` = lo pedido.
  IntColumn get cantidadAutorizada => integer().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
