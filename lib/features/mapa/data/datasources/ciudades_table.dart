import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `ciudad` de la DB local: el catálogo de ciudades del Admin (HU-UBI-001: `ubicacion.ciudad_id`
/// es una FK a ese catálogo). Réplica de solo lectura del canal de catálogo (contrato-sync-engine §2,
/// política `pull`): la app nunca la escribe.
///
/// Misma forma que `public.ciudad` (backend-supabase 0001), con las diferencias del motor de siempre
/// (ver `Ubicaciones`): fechas en epoch ms UTC, sin claves foráneas ni defaults de servidor. **Solo
/// las columnas que la app lee hoy**: el nombre y el centro (la propuesta de ciudad del alta mide la
/// distancia al centro). El servidor manda además `pais_id`, el rectángulo (0031), `departamento`
/// (0066) y `origen` (0109); el motor ignora lo que la tabla local no tiene, y cada una se suma
/// cuando una pantalla la pida (el rectángulo, con el paquete del mapa por ciudad, #189).
@DataClassName('CiudadFila')
class Ciudades extends Table {
  @override
  String get tableName => 'ciudad';

  TextColumn get id => text()();

  TextColumn get nombre => text()();

  /// Centro de la ciudad, en grados.
  RealColumn get latCentro => real()();

  RealColumn get lonCentro => real()();

  /// Zoom con el que se abre el mapa de la ciudad (1 a 22).
  IntColumn get zoomInicial => integer().withDefault(const Constant(13))();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete: una ciudad dada de baja deja de ofrecerse, pero las ubicaciones que ya la llevan
  /// la siguen resolviendo.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
