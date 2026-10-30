import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';
import 'productos_devueltos_converter.dart';

/// Tabla `devolucion` de la DB local cifrada (esquema-datos.md §Operaciones de campo, ADR-002).
///
/// Es la misma tabla que `public.devolucion` del cloud (`backend-supabase`, migraciones 0108, 0136 y
/// 0142), con las diferencias de motor de [Ventas]: fechas en epoch ms UTC, sin claves foráneas y sin
/// defaults de servidor. `colportor_id` lo fija el servidor desde el JWT y el push lo descarta: la app
/// no lo escribe y no está acá (el dueño es el de la venta).
///
/// La venta original **no se toca**: la devolución se anota aparte y el saldo se recalcula con ella. Una
/// venta puede tener varias devoluciones. El dinero va en **centavos** (`int`), nunca `double`.
///
/// **Sin dato del cliente** (ADR-004): cuelga de la venta por un id opaco. La única prosa que sube es el
/// [motivo], por decisión explícita de Cristian (27/10, «Motivo devol.»).
@DataClassName('DevolucionFila')
@TableIndex(name: 'devolucion_venta_idx', columns: {#ventaId})
class Devoluciones extends Table {
  @override
  String get tableName => 'devolucion';

  TextColumn get id => text()();

  /// La venta que se devuelve.
  TextColumn get ventaId => text()();

  /// `[{producto_id, cantidad, venta_item_id}]`: los libros que vuelven, cada uno con el renglón de la
  /// venta del que salió. Al menos un elemento; sin precios (salen del renglón).
  TextColumn get productosDevueltos => text().map(const ProductosDevueltosConverter())();

  /// Lo que la colportora se queda cuando el cliente pagó de más y elige «Lo retengo», en centavos;
  /// 0 si no retiene nada.
  IntColumn get dineroRetenido => integer().withDefault(const Constant(0))();

  /// Lo que se le devolvió al cliente en el momento («Se lo devuelvo ahora»), en centavos; `null` si
  /// no devolvió plata. «En mano» lo resta.
  IntColumn get montoReembolsado => integer().nullable()();

  /// Por qué se devuelve: de 1 a 500 caracteres, sin espacios en los bordes; `null` si no lo dijo.
  TextColumn get motivo => text().nullable()();

  /// Cuándo se registró, según el teléfono.
  IntColumn get fechaDevolucion => integer().map(const FechaUtcConverter())();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6): la baja de una devolución mal cargada. Nunca se
  /// borra.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (dinero_retenido >= 0)',
    'CHECK (monto_reembolsado IS NULL OR monto_reembolsado >= 0)',
    'CHECK (motivo IS NULL OR length(motivo) BETWEEN 1 AND 500)',
  ];
}
