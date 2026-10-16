import 'package:equatable/equatable.dart';

import 'coordenadas.dart';

/// Recuadro (bbox) visible del mapa, en grados (HU-UBI-003).
///
/// Si [oeste] > [este] el recuadro cruza el antimeridiano (longitud ±180): contiene las longitudes
/// `>= oeste` **o** `<= este`.
final class AreaMapa extends Equatable {
  const AreaMapa({required this.sur, required this.oeste, required this.norte, required this.este});

  final double sur;
  final double oeste;
  final double norte;
  final double este;

  /// Los cuatro bordes son números finitos dentro de rango y `sur <= norte`.
  bool get esValida =>
      [sur, oeste, norte, este].every((v) => v.isFinite) &&
      sur >= -90 &&
      norte <= 90 &&
      sur <= norte &&
      oeste >= -180 &&
      oeste <= 180 &&
      este >= -180 &&
      este <= 180;

  bool get cruzaAntimeridiano => oeste > este;

  /// Un área no válida no contiene nada.
  bool contiene(Coordenadas punto) {
    if (!esValida) return false;
    if (punto.lat < sur || punto.lat > norte) return false;
    return cruzaAntimeridiano
        ? punto.lon >= oeste || punto.lon <= este
        : punto.lon >= oeste && punto.lon <= este;
  }

  @override
  List<Object?> get props => [sur, oeste, norte, este];
}
