import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `precio_general` de la DB local: el precio de venta de un producto o un combo para todo el
/// país, que fija el Administrador (HU-CAT-008). Es el que rige en toda ciudad sin excepción en
/// `precio_por_ciudad`. Réplica de solo lectura del canal de catálogo (contrato-sync-engine §2,
/// política `pull`): la app nunca la escribe.
///
/// Misma forma que `public.precio_general` (backend-supabase 0034) y mismas decisiones que
/// `PreciosPorCiudad`: vigencias como texto `AAAA-MM-DD` y sin los índices de «un solo vigente».
///
/// **Hoy el servidor todavía no la publica** (no está en `sync.entidad`: backend-supabase 0034 la
/// dejó sin registrar hasta el OK del contrato). El pull ignora una entidad que el servidor no
/// conoce, así que la tabla queda vacía hasta que se registre, y entonces el teléfono la baja sin
/// tocar la app.
@DataClassName('PrecioGeneralFila')
@TableIndex(name: 'precio_general_producto_idx', columns: {#productoId})
@TableIndex(name: 'precio_general_coleccion_idx', columns: {#coleccionId})
class PreciosGenerales extends Table {
  @override
  String get tableName => 'precio_general';

  TextColumn get id => text()();

  /// El producto, o `null` si el precio es de un combo.
  TextColumn get productoId => text().nullable()();

  /// El combo, o `null` si el precio es de un producto.
  TextColumn get coleccionId => text().nullable()();

  /// Centavos.
  IntColumn get precioVenta => integer()();

  /// Primer día en que vale (inclusive), `AAAA-MM-DD`.
  TextColumn get validoDesde => text()();

  /// Último día en que vale (inclusive), `AAAA-MM-DD`; `null` = vigente hasta nuevo aviso.
  TextColumn get validoHasta => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

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
