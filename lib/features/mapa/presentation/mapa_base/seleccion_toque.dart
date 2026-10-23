import 'dart:math' as math;
import 'dart:ui';

import '../../domain/value_objects/coordenadas.dart';

/// Qué punto o grupo del mapa se tocó.
///
/// Un marcador mide ~23 dp, menos que el objetivo táctil mínimo (48 dp): preguntar solo por lo que
/// hay bajo el píxel tocado obliga a acertarle con la yema. Se pregunta por un área de 48 dp
/// alrededor del toque y, de lo que cae adentro, gana lo que está más cerca del dedo: con
/// marcadores vecinos no se abre el de al lado.
abstract final class SeleccionToque {
  /// El lado del área alrededor del toque, en dp.
  static const ladoDp = 48.0;

  /// El área alrededor de [punto], en las unidades en que la vista nativa lo da y lo consulta:
  /// [unidadesPorDp] es el factor de dp a esas unidades (la densidad de píxeles en Android, que
  /// trabaja en píxeles nativos, y 1 en iOS, que trabaja en puntos).
  static Rect area(math.Point<double> punto, {required double unidadesPorDp}) {
    final mitad = ladoDp / 2 * unidadesPorDp;
    return Rect.fromLTRB(punto.x - mitad, punto.y - mitad, punto.x + mitad, punto.y + mitad);
  }

  /// Con las casas acercadas (vista 39, M·02) el toque elige la más cercana **dentro de 44 dp**
  /// (decisión de Cristian del 23/10, «Números casas»; el mismo radio que aplicó el #462 para las
  /// casas en un mismo punto).
  static const radioDeCuadradosDp = 44.0;

  /// El área alrededor de [punto] donde se consultan los cuadrados: un cuadrado de ±44 dp, así
  /// entran los que tienen el centro a 44 dp aunque su dibujo (de 40 dp) quede apenas fuera. Después
  /// [masCercano] descarta los que pasan de [radioDeCuadradosDp].
  static Rect areaDeCuadrados(math.Point<double> punto, {required double unidadesPorDp}) {
    final mitad = radioDeCuadradosDp * unidadesPorDp;
    return Rect.fromLTRB(punto.x - mitad, punto.y - mitad, punto.x + mitad, punto.y + mitad);
  }

  /// El de [hallados] (los `Feature` GeoJSON de la consulta) más cercano a [toque]; `null` si
  /// ninguno es un punto con coordenadas. A igual distancia gana el primero, o sea el de la capa
  /// de más arriba.
  ///
  /// Con [maximoMetros] solo cuentan los que están a esa distancia o menos del toque: si ninguno,
  /// `null` (el toque cae en el mapa).
  static Object? masCercano(Iterable<Object?> hallados, Coordenadas toque, {double? maximoMetros}) {
    Object? mejor;
    var distanciaMejor = double.infinity;
    for (final elemento in hallados) {
      final posicion = _posicion(elemento);
      if (posicion == null) continue;
      final distancia = toque.distanciaMetrosA(posicion);
      if (maximoMetros != null && distancia > maximoMetros) continue;
      if (distancia < distanciaMejor) {
        distanciaMejor = distancia;
        mejor = elemento;
      }
    }
    return mejor;
  }

  static Coordenadas? _posicion(Object? elemento) {
    if (elemento is! Map<String, dynamic>) return null;
    final geometria = elemento['geometry'];
    if (geometria is! Map<String, dynamic>) return null;
    final coordenadas = geometria['coordinates'];
    if (coordenadas is! List<dynamic> || coordenadas.length < 2) return null;
    final lon = coordenadas[0];
    final lat = coordenadas[1];
    if (lon is! num || lat is! num) return null;
    return Coordenadas(lat: lat.toDouble(), lon: lon.toDouble());
  }
}
