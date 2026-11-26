import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `campania_coordinador` de la DB local (esquema-datos.md §campania_coordinador, HU-JOR-003): los
/// coordinadores de cada campaña, una fila por (campaña, coordinador). Réplica de **solo lectura**
/// (política `pull`, backend-supabase 0178, #254): la llena el servidor y el teléfono no la escribe.
///
/// De ahí sale la lista de «¿Quién te acompaña?» (vista 20): la colportora recibe solo a los coordinadores
/// de las campañas en las que está inscripta, con su nombre y su apellido y nada más (nunca el correo ni el
/// teléfono). El que deja de contar (cuenta suspendida o de baja, rol vencido o quitado) no cambia de fila:
/// el pull lo avisa con `out_of_area` (0200) y la app lo marca en `sync_fuera_del_area` sin borrarlo.
///
/// Misma forma que `public.campania_coordinador`, con las diferencias de siempre del motor: fechas en
/// epoch ms UTC, sin claves foráneas ni defaults de servidor.
@DataClassName('CampaniaCoordinadorFila')
@TableIndex(name: 'campania_coordinador_campania_idx', columns: {#campaniaId})
class CampaniaCoordinadores extends Table {
  @override
  String get tableName => 'campania_coordinador';

  TextColumn get id => text()();

  TextColumn get campaniaId => text()();

  /// La cuenta del coordinador: es lo que se sube como `jornada_acompaniante.acompaniante_id`.
  TextColumn get usuarioId => text()();

  /// Copia del nombre y del apellido del perfil (el teléfono no puede leer `usuario`).
  TextColumn get nombre => text()();

  TextColumn get apellido => text()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
