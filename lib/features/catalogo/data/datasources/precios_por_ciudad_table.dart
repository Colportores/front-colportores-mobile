import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `precio_por_ciudad` de la DB local: las excepciones al precio general, el precio de venta
/// de un producto o un combo en una ciudad de la campaña (HU-CAT-005). Réplica de solo lectura del
/// canal de catálogo (contrato-sync-engine §2, política `pull`, con Realtime).
///
/// Misma forma que `public.precio_por_ciudad` (backend-supabase 0030), con las diferencias del
/// motor de siempre (ver `Ubicaciones`). **Las vigencias son `date` en el cloud y acá texto
/// `AAAA-MM-DD`**, tal cual llegan: no son un instante, y pasarlas por epoch ms las correría un
/// día según la zona del teléfono (el servidor las fija por el día de Montevideo). Comparan bien
/// como texto. **Sin los índices de «un solo vigente a la vez»**: el servidor ya los garantiza y un
/// índice único local podría frenar un delta válido a mitad de camino.
@DataClassName('PrecioPorCiudadFila')
@TableIndex(name: 'precio_por_ciudad_campania_ciudad_idx', columns: {#campaniaCiudadId})
@TableIndex(name: 'precio_por_ciudad_producto_idx', columns: {#productoId})
@TableIndex(name: 'precio_por_ciudad_coleccion_idx', columns: {#coleccionId})
class PreciosPorCiudad extends Table {
  @override
  String get tableName => 'precio_por_ciudad';

  TextColumn get id => text()();

  /// El producto, o `null` si el precio es de un combo.
  TextColumn get productoId => text().nullable()();

  /// El combo, o `null` si el precio es de un producto.
  TextColumn get coleccionId => text().nullable()();

  TextColumn get campaniaCiudadId => text()();

  /// Centavos.
  IntColumn get precioVenta => integer()();

  /// Primer día en que vale (inclusive), `AAAA-MM-DD`.
  TextColumn get validoDesde => text()();

  /// Último día en que vale (inclusive), `AAAA-MM-DD`; `null` = vigente hasta nuevo aviso.
  TextColumn get validoHasta => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: una excepción quitada vuelve a valer el precio general.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK ((producto_id IS NULL) <> (coleccion_id IS NULL))',
    'CHECK (precio_venta >= 0)',
    'CHECK (valido_hasta IS NULL OR valido_hasta >= valido_desde)',
  ];
}
