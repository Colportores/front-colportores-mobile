import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `producto` de la DB local: el catálogo de lo que se vende (libros, revistas, material y
/// ejemplares misioneros). Réplica de solo lectura del canal de catálogo (contrato-sync-engine §2,
/// política `pull`, con Realtime): la app nunca la escribe.
///
/// Misma forma que `public.producto` (backend-supabase 0001), con las diferencias del motor de
/// siempre (ver `Ubicaciones`): fechas en epoch ms UTC, sin claves foráneas ni defaults de
/// servidor. **Sin el `CHECK` de `tipo`**: si el servidor suma un tipo, un teléfono con la versión
/// vieja de la app no puede frenar todo el pull por una fila que todavía no entiende.
@DataClassName('ProductoFila')
class Productos extends Table {
  @override
  String get tableName => 'producto';

  TextColumn get id => text()();

  TextColumn get nombre => text()();

  TextColumn get descripcion => text().nullable()();

  /// `LIBRO`, `REVISTA`, `MATERIAL` o `MISIONERO`.
  TextColumn get tipo => text()();

  /// Cuenta para la beca del colportor (el icono 🏆 de la vista 26).
  BoolColumn get esBonificable => boolean().withDefault(const Constant(false))();

  /// Ejemplar misionero: se entrega, no se vende.
  BoolColumn get esMisionero => boolean().withDefault(const Constant(false))();

  /// Lo que paga el colportor a la casa editora, en centavos. `null` si no está cargado.
  IntColumn get precioBaseCompra => integer().nullable()();

  TextColumn get casaEditora => text().nullable()();

  TextColumn get imagenUrl => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: un producto dado de baja deja de ofrecerse, pero las ventas que ya lo llevan lo
  /// siguen resolviendo.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  /// El código que le asignó la casa editora (`producto.codigo_editor`, backend-supabase 0070):
  /// opcional y no único, de 1 a 50 caracteres. Sin código el producto se encuentra por nombre. Va
  /// al final porque llegó con la versión 18 del esquema (`ALTER TABLE … ADD COLUMN`).
  TextColumn get codigoEditor => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (precio_base_compra IS NULL OR precio_base_compra >= 0)',
  ];
}
