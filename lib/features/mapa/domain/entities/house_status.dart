import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import 'color_house_status.dart';
import 'ubicacion.dart';

/// La cache del color de una casa (ADR-003, esquema-datos.md §`house_status`): **una fila por
/// ubicación**, con su punto desnormalizado para pintar el mapa sin JOINs.
///
/// Sube al cloud (`push`, para el coordinador) y por eso **no tiene dato de persona**: solo la casa,
/// su punto y su color (ADR-003, ADR-004). No guarda zona.
class HouseStatus extends Equatable {
  const HouseStatus({
    required this.ubicacionId,
    required this.lat,
    required this.lon,
    required this.tipoUbicacion,
    required this.color,
    required this.auditoria,
  });

  /// Clave de la fila (`ubicacion_id`): FK a `ubicacion.id`.
  final String ubicacionId;

  final double lat;
  final double lon;

  final TipoUbicacion tipoUbicacion;

  final ColorHouseStatus color;

  final Auditoria auditoria;

  /// 1 a 7, el mismo dato que [color] (`house_status.prioridad`).
  int get prioridad => color.prioridad;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [ubicacionId, lat, lon, tipoUbicacion, color, auditoria];
}
