import 'package:drift/drift.dart';

import '../core/database/fecha_utc_converter.dart';

// Las réplicas del catálogo (contrato-sync-engine §2, política `pull`): la app **nunca las
// escribe**; las llena el pull del motor (`DriftLocalStore`) y las lee quien las necesite (los
// precios de HU-CAT-006, las ciudades del alta, las inscripciones de HU-CAM-006).
//
// Cada columna se llama como en el cloud y tiene su tipo: `uuid` y `text` como texto, `date` como
// texto ISO (`2026-10-16`: un día de calendario no es un instante y no tiene zona), `timestamptz`
// en epoch ms con [FechaUtcConverter], los enteros como enteros, `double precision` como real y
// `boolean` como bool. Sin FK entre ellas: el pull trae las filas en el orden que quiere, y una
// réplica a medio bajar no puede romper por eso.
//
// Las columnas de sync (`created_at` … `sync_version`) son las de toda tabla del repo; `xmin_w`
// es del servidor y no baja.

mixin _ColumnasDeSync on Table {
  TextColumn get id => text()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// `pais`.
@DataClassName('PaisFila')
class ReplicaPaises extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'pais';

  TextColumn get nombre => text()();

  /// ISO 3166-1 alfa-2 (`UY`).
  TextColumn get isoCode => text()();
}

/// `ciudad`, con el rectángulo de su mapa (backend 0031).
@DataClassName('CiudadFila')
class ReplicaCiudades extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'ciudad';

  TextColumn get nombre => text()();

  TextColumn get paisId => text()();

  RealColumn get latCentro => real()();

  RealColumn get lonCentro => real()();

  IntColumn get zoomInicial => integer()();

  RealColumn get bboxOeste => real().nullable()();

  RealColumn get bboxSur => real().nullable()();

  RealColumn get bboxEste => real().nullable()();

  RealColumn get bboxNorte => real().nullable()();
}

/// `campania`: las de las inscripciones del colportor (la RLS decide cuáles bajan).
@DataClassName('CampaniaFila')
class ReplicaCampanias extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'campania';

  TextColumn get nombre => text()();

  TextColumn get tipo => text()();

  /// `date`, ISO.
  TextColumn get fechaInicio => text()();

  /// `date`, ISO. Sin fin, la campaña sigue abierta.
  TextColumn get fechaFin => text().nullable()();

  TextColumn get coordinadorId => text().nullable()();
}

/// `campania_colportor`: **solo las inscripciones propias** (RLS). De acá sale la zona del
/// colportor en cada campaña (HU-CAM-006, el aviso «Te asignaron la zona…»).
@DataClassName('CampaniaColportorFila')
@TableIndex(name: 'campania_colportor_usuario_idx', columns: {#usuarioId})
class ReplicaCampaniasColportor extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'campania_colportor';

  TextColumn get campaniaId => text()();

  TextColumn get usuarioId => text()();

  TextColumn get zonaId => text().nullable()();

  IntColumn get metaLibros => integer().nullable()();
}

/// `producto`. Realtime: un cambio del administrador baja al instante (§5.6).
@DataClassName('ProductoFila')
class ReplicaProductos extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'producto';

  TextColumn get nombre => text()();

  TextColumn get descripcion => text().nullable()();

  TextColumn get tipo => text()();

  BoolColumn get esBonificable => boolean()();

  BoolColumn get esMisionero => boolean()();

  /// En pesos, sin decimales (como en el cloud).
  IntColumn get precioBaseCompra => integer().nullable()();

  TextColumn get casaEditora => text().nullable()();

  TextColumn get imagenUrl => text().nullable()();
}

/// `coleccion`. Realtime.
@DataClassName('ColeccionFila')
class ReplicaColecciones extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'coleccion';

  TextColumn get nombre => text()();
}

/// `producto_coleccion`: qué productos forman cada colección. Realtime.
@DataClassName('ProductoColeccionFila')
@TableIndex(name: 'producto_coleccion_coleccion_idx', columns: {#coleccionId})
class ReplicaProductosColeccion extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'producto_coleccion';

  TextColumn get productoId => text()();

  TextColumn get coleccionId => text()();
}

/// `precio_por_ciudad`: el precio de venta de un producto o una colección en una ciudad de la
/// campaña, con su vigencia (backend 0030 y 0034). Realtime.
@DataClassName('PrecioPorCiudadFila')
@TableIndex(name: 'precio_por_ciudad_campania_ciudad_idx', columns: {#campaniaCiudadId})
class ReplicaPreciosPorCiudad extends Table with _ColumnasDeSync {
  @override
  String get tableName => 'precio_por_ciudad';

  TextColumn get campaniaCiudadId => text()();

  TextColumn get productoId => text().nullable()();

  TextColumn get coleccionId => text().nullable()();

  /// En pesos, sin decimales.
  IntColumn get precioVenta => integer()();

  /// `date`, ISO.
  TextColumn get validoDesde => text()();

  /// `date`, ISO. Sin fin, vigente.
  TextColumn get validoHasta => text().nullable()();
}

/// `sync_fuera_del_area`: las filas que el motor marcó «fuera del área» (§2.1). **Nada se borra
/// por esto**: la fila sigue en su tabla, y la app decide si la muestra (R-UB12, solo visual).
///
/// [confirmada] separa lo que ya se sabe que quedó afuera de lo que está a la espera de volver a
/// bajar después de un `area_reset`: hasta la última página de esa descarga, una casa que todavía
/// no bajó no está afuera. La app lee solo las confirmadas. Una fila que vuelve a bajar se borra
/// de acá.
@DataClassName('FueraDelAreaFila')
class SyncFueraDelArea extends Table {
  @override
  String get tableName => 'sync_fuera_del_area';

  TextColumn get entidad => text()();

  TextColumn get filaId => text()();

  BoolColumn get confirmada => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {entidad, filaId};
}
