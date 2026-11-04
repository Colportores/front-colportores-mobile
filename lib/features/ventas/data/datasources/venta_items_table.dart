import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';
import 'componentes_converter.dart';

/// Tabla `venta_item` de la DB local cifrada (esquema-datos.md §Operaciones de campo).
///
/// Es la misma tabla que `public.venta_item` del cloud (`backend-supabase`, migraciones 0001, 0056 y
/// 0071), con los mismos `CHECK`: el ítem es un producto **o** un combo (exactamente uno de
/// [productoId] y [coleccionId]), `subtotal = cantidad × precio_unitario` y [componentes] va en un
/// combo y solo en un combo. Fechas en epoch ms UTC, sin claves foráneas.
///
/// [precioUnitario] es la **foto** del precio al vender: cambiar el catálogo después no toca ninguna
/// venta. [componentes] es lo que traía **una unidad** del combo (lo fijo y los libros que eligió),
/// copiado al vender por la misma razón (decisión de Cristian, 23/10, «Combo vendido»).
@DataClassName('VentaItemFila')
@TableIndex(name: 'venta_item_venta_idx', columns: {#ventaId})
class VentaItems extends Table {
  @override
  String get tableName => 'venta_item';

  TextColumn get id => text()();

  TextColumn get ventaId => text()();

  /// El producto vendido; `null` si el ítem es un combo.
  TextColumn get productoId => text().nullable()();

  /// El combo vendido como un solo ítem; `null` si el ítem es un producto.
  TextColumn get coleccionId => text().nullable()();

  IntColumn get cantidad => integer()();

  /// En centavos.
  IntColumn get precioUnitario => integer()();

  /// En centavos.
  IntColumn get subtotal => integer()();

  /// `[{producto_id, cantidad}]` de una unidad del combo; `null` en un producto suelto.
  TextColumn get componentes => text().nullable().map(const ComponentesConverter())();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (cantidad > 0)',
    'CHECK (precio_unitario >= 0)',
    'CHECK (subtotal = cantidad * precio_unitario)',
    'CHECK ((producto_id IS NULL) <> (coleccion_id IS NULL))',
    'CHECK ((coleccion_id IS NULL) = (componentes IS NULL))',
  ];
}
