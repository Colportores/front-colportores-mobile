import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import 'auditoria_json.dart';

/// Una fila de `zona` del canal de catálogo, con la forma de backend-supabase 0008: cuelga de
/// [campaniaCiudadId] y su forma es [poligonoGeojson] (lo que se dibuja y con lo que se ubica cada
/// dirección). [tipoForma] dice cómo se armó: `RADIAL` ([centroLat], [centroLon], [radioM]) o
/// `ESQUINAS` (sus `zona_vertice`).
///
/// [fromJson] lee la fila del delta del pull (todas las columnas menos `xmin_w`; el `jsonb` llega
/// como objeto) y [toJson] la devuelve igual. [fromFila] y [aFila] la pasan de y a la tabla local
/// `Zonas`. La app nunca la escribe por su cuenta: es una réplica.
final class ZonaModel extends Equatable {
  const ZonaModel({
    required this.id,
    required this.nombre,
    required this.campaniaCiudadId,
    required this.tipoForma,
    this.centroLat,
    this.centroLon,
    this.radioM,
    required this.poligonoGeojson,
    this.color,
    required this.auditoria,
  });

  factory ZonaModel.fromJson(Map<String, Object?> json) => ZonaModel(
    id: json['id']! as String,
    nombre: json['nombre']! as String,
    campaniaCiudadId: json['campania_ciudad_id']! as String,
    tipoForma: json['tipo_forma']! as String,
    centroLat: (json['centro_lat'] as num?)?.toDouble(),
    centroLon: (json['centro_lon'] as num?)?.toDouble(),
    radioM: (json['radio_m'] as num?)?.toInt(),
    poligonoGeojson: _geojson(json['poligono_geojson']),
    color: json['color'] as String?,
    auditoria: auditoriaDesdeJson(json),
  );

  factory ZonaModel.fromFila(ZonaFila fila) => ZonaModel(
    id: fila.id,
    nombre: fila.nombre,
    campaniaCiudadId: fila.campaniaCiudadId,
    tipoForma: fila.tipoForma,
    centroLat: fila.centroLat,
    centroLon: fila.centroLon,
    radioM: fila.radioM,
    poligonoGeojson: fila.poligonoGeojson,
    color: fila.color,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  final String id;
  final String nombre;
  final String campaniaCiudadId;

  /// `RADIAL` o `ESQUINAS`.
  final String tipoForma;

  final double? centroLat;
  final double? centroLon;

  /// Solo `RADIAL`, en metros.
  final int? radioM;

  /// `Polygon` GeoJSON en `[lon, lat]`, ya decodificado.
  final Map<String, Object?> poligonoGeojson;

  /// `#RRGGBB`, o `null`.
  final String? color;

  final Auditoria auditoria;

  ZonaFila aFila() => ZonaFila(
    id: id,
    nombre: nombre,
    campaniaCiudadId: campaniaCiudadId,
    tipoForma: tipoForma,
    centroLat: centroLat,
    centroLon: centroLon,
    radioM: radioM,
    poligonoGeojson: poligonoGeojson,
    color: color,
    createdAt: auditoria.createdAt,
    updatedAt: auditoria.updatedAt,
    createdBy: auditoria.createdBy,
    deletedAt: auditoria.deletedAt,
    syncVersion: auditoria.syncVersion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'campania_ciudad_id': campaniaCiudadId,
    'tipo_forma': tipoForma,
    'centro_lat': centroLat,
    'centro_lon': centroLon,
    'radio_m': radioM,
    'poligono_geojson': poligonoGeojson,
    'color': color,
    ...auditoriaAJson(auditoria),
  };

  /// El `jsonb` llega como objeto; si algún transporte lo manda serializado, se decodifica.
  static Map<String, Object?> _geojson(Object? valor) => switch (valor) {
    final Map<String, Object?> objeto => objeto,
    final String texto => jsonDecode(texto) as Map<String, Object?>,
    _ => throw const FormatException('poligono_geojson no es un objeto GeoJSON'),
  };

  @override
  List<Object?> get props => [
    id,
    nombre,
    campaniaCiudadId,
    tipoForma,
    centroLat,
    centroLon,
    radioM,
    poligonoGeojson,
    color,
    auditoria,
  ];
}
