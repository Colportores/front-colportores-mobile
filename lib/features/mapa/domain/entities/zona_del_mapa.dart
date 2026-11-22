import 'package:equatable/equatable.dart';

import '../value_objects/geometria_zona.dart';

/// Una zona de una campaña del colportor, tal como se dibuja sobre el mapa (HU-UBI-003, #511): su
/// forma, su nombre y el color que le puso el coordinador.
///
/// Solo trae zonas **vivas** de campañas en las que el colportor sigue inscripto y que no
/// terminaron. [propia] dice si es la zona que le asignaron al colportor en esa inscripción
/// (`campania_colportor.zona_id`): el mapa la resalta y deja las demás tenues.
final class ZonaDelMapa extends Equatable {
  const ZonaDelMapa({
    required this.id,
    required this.nombre,
    required this.geometria,
    this.color,
    this.propia = false,
  });

  final String id;
  final String nombre;

  /// La forma de la zona (`zona.poligono_geojson`).
  final GeometriaZona geometria;

  /// `#RRGGBB` tal cual lo guardó el coordinador, o `null` si no eligió uno.
  final String? color;

  /// Es la zona asignada al colportor.
  final bool propia;

  @override
  List<Object?> get props => [id, nombre, geometria, color, propia];
}
