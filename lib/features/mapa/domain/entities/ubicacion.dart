import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Dirección física (esquema-datos.md §Modelo de Espacio, tabla `ubicacion`).
///
/// Regla de integridad "una sola entrada por (calle, número, ciudad)" es de unicidad entre
/// filas: no se puede validar en el constructor de una entidad aislada, se enforcea en el
/// repositorio/DB (índice único).
enum TipoUbicacion { casa, negocio, edificio }

class Ubicacion extends Equatable {
  const Ubicacion({
    required this.id,
    required this.tipo,
    required this.calle,
    required this.numero,
    required this.lat,
    required this.lon,
    required this.ciudadId,
    required this.zonaId,
    required this.auditoria,
  });

  final String id;
  final TipoUbicacion tipo;
  final String calle;
  final String numero;
  final double lat;
  final double lon;

  /// FK a `ciudad.id` (Geografía, fuera del alcance de #8 — se referencia por id).
  final String ciudadId;

  /// FK a `zona.id` (Geografía, fuera del alcance de #8 — se referencia por id).
  final String zonaId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, tipo, calle, numero, lat, lon, ciudadId, zonaId, auditoria];
}
