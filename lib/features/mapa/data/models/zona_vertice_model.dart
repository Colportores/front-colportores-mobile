import 'package:equatable/equatable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import 'auditoria_json.dart';

/// Una fila de `zona_vertice` del canal de catálogo (backend-supabase 0008): la esquina número
/// [orden] de la zona `ESQUINAS` [zonaId], con los nombres de sus calles para mostrar.
///
/// [fromJson] lee la fila del delta del pull (todas las columnas menos `xmin_w`) y [toJson] la
/// devuelve igual. [fromFila] y [aFila] la pasan de y a la tabla local `ZonaVertices`. La app nunca
/// la escribe por su cuenta: es una réplica.
final class ZonaVerticeModel extends Equatable {
  const ZonaVerticeModel({
    required this.id,
    required this.zonaId,
    required this.orden,
    required this.lat,
    required this.lon,
    this.calleA,
    this.calleB,
    required this.auditoria,
  });

  factory ZonaVerticeModel.fromJson(Map<String, Object?> json) => ZonaVerticeModel(
    id: json['id']! as String,
    zonaId: json['zona_id']! as String,
    orden: (json['orden']! as num).toInt(),
    lat: (json['lat']! as num).toDouble(),
    lon: (json['lon']! as num).toDouble(),
    calleA: json['calle_a'] as String?,
    calleB: json['calle_b'] as String?,
    auditoria: auditoriaDesdeJson(json),
  );

  factory ZonaVerticeModel.fromFila(ZonaVerticeFila fila) => ZonaVerticeModel(
    id: fila.id,
    zonaId: fila.zonaId,
    orden: fila.orden,
    lat: fila.lat,
    lon: fila.lon,
    calleA: fila.calleA,
    calleB: fila.calleB,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  final String id;
  final String zonaId;
  final int orden;
  final double lat;
  final double lon;
  final String? calleA;
  final String? calleB;
  final Auditoria auditoria;

  ZonaVerticeFila aFila() => ZonaVerticeFila(
    id: id,
    zonaId: zonaId,
    orden: orden,
    lat: lat,
    lon: lon,
    calleA: calleA,
    calleB: calleB,
    createdAt: auditoria.createdAt,
    updatedAt: auditoria.updatedAt,
    createdBy: auditoria.createdBy,
    deletedAt: auditoria.deletedAt,
    syncVersion: auditoria.syncVersion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'zona_id': zonaId,
    'orden': orden,
    'lat': lat,
    'lon': lon,
    'calle_a': calleA,
    'calle_b': calleB,
    ...auditoriaAJson(auditoria),
  };

  @override
  List<Object?> get props => [id, zonaId, orden, lat, lon, calleA, calleB, auditoria];
}
