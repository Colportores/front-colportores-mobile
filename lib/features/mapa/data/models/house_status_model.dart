import '../../domain/entities/house_status.dart';
import 'auditoria_json.dart';
import 'ubicacion_model.dart';

/// DTO de [HouseStatus]: la entidad más su payload de sync. [toJson] usa los nombres de columna de
/// `public.house_status` (`backend-supabase`, migración 0001 y 0011: sin `zona_id`) y las fechas en
/// ISO-8601 UTC. Es la fila entera, **sin ningún dato de persona** (ADR-003, ADR-004); un test fija
/// la lista exacta de claves contra las columnas de la tabla local.
final class HouseStatusModel extends HouseStatus {
  const HouseStatusModel({
    required super.ubicacionId,
    required super.lat,
    required super.lon,
    required super.tipoUbicacion,
    required super.color,
    required super.auditoria,
  });

  factory HouseStatusModel.fromEntity(HouseStatus estado) => HouseStatusModel(
    ubicacionId: estado.ubicacionId,
    lat: estado.lat,
    lon: estado.lon,
    tipoUbicacion: estado.tipoUbicacion,
    color: estado.color,
    auditoria: estado.auditoria,
  );

  Map<String, Object?> toJson() => {
    'ubicacion_id': ubicacionId,
    'lat': lat,
    'lon': lon,
    'tipo_ubicacion': UbicacionModel.codigoDeTipo(tipoUbicacion),
    'color': color.codigo,
    'prioridad': prioridad,
    ...auditoriaAJson(auditoria),
  };
}
