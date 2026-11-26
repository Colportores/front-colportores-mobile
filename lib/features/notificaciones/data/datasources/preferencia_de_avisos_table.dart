import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';
import '../../../../core/database/objeto_json_converter.dart';

/// Tabla `preferencia_de_avisos` de la DB local: las preferencias de avisos de la colportora, **una fila por
/// persona** (su `id` es el de la persona; backend-supabase 0207, #313, «Avisos s/red» de Cristian, 24/11,
/// HU-NOT-004). Viaja por el sync en las dos direcciones (contrato §2): baja con el pull y sube con el push
/// como cualquier fila, así que un cambio hecho sin señal queda en el teléfono al instante y sube después.
/// Si hay dos teléfonos rige el último cambio del motor (`conflict` para el segundo).
///
/// [notifPreferences] es el mismo objeto json que `usuario.notif_preferences` (los interruptores y las dos
/// horas de los avisos), guardado como texto y sin datos personales; `null` son los valores de siempre.
///
/// Misma forma que `public.preferencia_de_avisos`, con las diferencias del motor de siempre (ver
/// `Ubicaciones`): fechas en epoch ms UTC, sin claves foráneas ni defaults de servidor.
@DataClassName('PreferenciaDeAvisosFila')
class PreferenciasDeAvisos extends Table {
  @override
  String get tableName => 'preferencia_de_avisos';

  /// El id de la persona.
  TextColumn get id => text()();

  /// El objeto json de las preferencias, guardado como texto (`jsonEncode`), o `null`.
  TextColumn get notifPreferences => text().nullable().map(const ObjetoJsonConverter())();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// La fila no se da de baja: el servidor descarta la baja lógica.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
