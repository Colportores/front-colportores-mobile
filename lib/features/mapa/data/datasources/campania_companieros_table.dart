import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `campania_companiero` de la DB local: los **compañeros de campaña** de la colportora, o sea las
/// personas inscriptas en las mismas campañas que ella, con el nombre, el apellido y la ciudad y nada más
/// (backend-supabase 0208, #313, «Nombres camp.» de Cristian, 24/11). Réplica de **solo bajada**
/// (contrato §2, política `pull`, sigue las campañas de la persona): la mantiene el servidor y el teléfono
/// no la escribe. Sin correo, teléfono, cédula ni stock: la tabla no tiene esas columnas.
///
/// De acá salen los nombres de «Elegir colportor» (40A·02) y de la lista de colportores de la campaña
/// (40B·01). Una persona que dejó la campaña llega con `deleted_at`.
///
/// Misma forma que `public.campania_companiero`, con las diferencias del motor de siempre (ver
/// `Ubicaciones`): fechas en epoch ms UTC, sin claves foráneas ni defaults de servidor.
@DataClassName('CampaniaCompanieroFila')
@TableIndex(name: 'campania_companiero_campania_idx', columns: {#campaniaId})
class CampaniaCompanieros extends Table {
  @override
  String get tableName => 'campania_companiero';

  TextColumn get id => text()();

  TextColumn get campaniaId => text()();

  /// La persona inscripta (su `usuario.id`).
  TextColumn get usuarioId => text()();

  TextColumn get nombre => text().withDefault(const Constant(''))();

  TextColumn get apellido => text().withDefault(const Constant(''))();

  /// La ciudad de su inscripción, o `null` si no la tiene.
  TextColumn get ciudadId => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: la persona ya no está en la campaña.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
