import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `campania_colportor` de la DB local: las inscripciones **propias** del colportor en una
/// campaña, con la zona que le asignó el coordinador. Réplica de solo lectura del canal de catálogo
/// (contrato-sync-engine §2, política `pull`): la app nunca la escribe. El servidor solo baja las
/// filas del usuario autenticado (`sync.entidad.columna_duenio`, backend-supabase 0014), así que
/// `usuario_id` es siempre el de esta sesión.
///
/// Misma forma que `public.campania_colportor` (backend-supabase 0001 y 0006), con las diferencias
/// del motor de siempre (ver `Ubicaciones`). **Sin el `UNIQUE (campania_id, usuario_id)`**: la réplica
/// aplica las filas del delta de a una y el servidor ya lo garantiza. Una inscripción dada de baja
/// llega con `deleted_at` y la zona en `null`.
@DataClassName('CampaniaColportorFila')
@TableIndex(name: 'campania_colportor_usuario_idx', columns: {#usuarioId})
class CampaniasColportor extends Table {
  @override
  String get tableName => 'campania_colportor';

  TextColumn get id => text()();

  TextColumn get campaniaId => text()();

  TextColumn get usuarioId => text()();

  /// La zona asignada, o `null`: inscripto pero «sin zona».
  TextColumn get zonaId => text().nullable()();

  /// Snapshot de la beca a la carrera al momento de la asignación; `null` = sin meta.
  IntColumn get metaLibros => integer().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: lo sacaron de la campaña (HU-CAM-005).
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['CHECK (meta_libros IS NULL OR meta_libros >= 0)'];
}
