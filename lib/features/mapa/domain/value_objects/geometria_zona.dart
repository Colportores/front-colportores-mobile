import 'package:equatable/equatable.dart';

import 'coordenadas.dart';

/// La forma de una zona (`zona.poligono_geojson`): un `Polygon` o un `MultiPolygon` de GeoJSON,
/// con las coordenadas en `[lon, lat]`.
///
/// Es lo que dibujan la app y el panel y con lo que se ubica cada dirección (backend-supabase
/// 0008). [cubre] es el `ST_Covers` del servidor (0010): cálculo plano sobre lon/lat, **con el
/// borde incluido**, así que un punto justo en la calle que separa dos zonas lo cubren las dos (el
/// desempate lo hace `ZonaPorPosicion`).
///
/// **Misma regla que PostGIS**, no una más exacta: para un punto contra un polígono, `ST_Covers`
/// usa `point_in_ring` (`lwgeom_functions_analytic.c`, PostGIS 3.3), que calcula de qué lado del
/// lado está el punto con `determineSide` en `double` y toma el borde con `side == 0.0`. Se porta
/// literal, con el mismo orden de operandos, así el redondeo da lo mismo que en el servidor: un
/// punto que el `double` pone sobre un lado cuenta como borde aunque, con aritmética exacta, quede
/// apenas afuera. La única diferencia posible es que el compilador de C del servidor contraiga
/// `a * b - c * d` en una FMA (en otra arquitectura); Dart no lo hace.
final class GeometriaZona extends Equatable {
  const GeometriaZona._(this.poligonos);

  /// Cada polígono es su anillo exterior seguido de sus huecos; cada anillo, sus puntos en orden y
  /// **cerrado** (el último igual al primero: si el GeoJSON no lo cierra, se cierra al leerlo, como
  /// hace PostGIS).
  final List<List<List<Coordenadas>>> poligonos;

  /// Los lados más cortos que esto (al cuadrado) no cuentan: `point_in_ring` los saltea.
  static const double _largoMinimoAlCuadrado = 1e-12 * 1e-12;

  /// La geometría de [geojson] (el objeto ya decodificado), o `null` si no es un `Polygon` ni un
  /// `MultiPolygon` bien formado: anillos de al menos 3 puntos, cada punto `[lon, lat]` numérico.
  /// El servidor valida la forma al guardarla (0008), así que `null` sería un dato roto.
  static GeometriaZona? desdeGeojson(Object? geojson) {
    if (geojson is! Map<Object?, Object?>) return null;
    final coordenadas = geojson['coordinates'];
    final List<Object?> crudos;
    switch (geojson['type']) {
      case 'Polygon':
        crudos = [coordenadas];
      case 'MultiPolygon' when coordenadas is List<Object?>:
        crudos = coordenadas;
      default:
        return null;
    }
    final poligonos = <List<List<Coordenadas>>>[];
    for (final crudo in crudos) {
      final poligono = _poligono(crudo);
      if (poligono == null) return null;
      poligonos.add(poligono);
    }
    return poligonos.isEmpty ? null : GeometriaZona._(poligonos);
  }

  /// `true` si [punto] está adentro de algún polígono o sobre su borde (el exterior o el de un
  /// hueco). Un punto dentro de un hueco queda afuera.
  bool cubre(Coordenadas punto) => poligonos.any((anillos) => _enPoligono(anillos, punto) >= 0);

  static List<List<Coordenadas>>? _poligono(Object? crudo) {
    if (crudo is! List<Object?> || crudo.isEmpty) return null;
    final anillos = <List<Coordenadas>>[];
    for (final anillo in crudo) {
      final puntos = _anillo(anillo);
      if (puntos == null) return null;
      anillos.add(puntos);
    }
    return anillos;
  }

  static List<Coordenadas>? _anillo(Object? crudo) {
    if (crudo is! List<Object?> || crudo.length < 3) return null;
    final puntos = <Coordenadas>[];
    for (final punto in crudo) {
      if (punto is! List<Object?> || punto.length < 2) return null;
      final [lon, lat, ...] = punto;
      if (lon is! num || lat is! num) return null;
      puntos.add(Coordenadas(lat: lat.toDouble(), lon: lon.toDouble()));
    }
    if (puntos.first != puntos.last) puntos.add(puntos.first);
    return puntos;
  }

  /// `point_in_polygon` de PostGIS: -1 afuera, 0 en el borde, 1 adentro. Afuera del exterior es
  /// afuera; adentro de un hueco, afuera; en el borde de un hueco, borde.
  static int _enPoligono(List<List<Coordenadas>> anillos, Coordenadas p) {
    final exterior = _enAnillo(anillos.first, p);
    if (exterior == -1) return -1;
    for (final hueco in anillos.skip(1)) {
      final enHueco = _enAnillo(hueco, p);
      if (enHueco == 1) return -1;
      if (enHueco == 0) return 0;
    }
    return exterior;
  }

  /// `point_in_ring` de PostGIS: número de vueltas, con el borde (`side == 0.0` y el punto dentro
  /// del recuadro del lado) primero. -1 afuera, 0 en el borde, 1 adentro.
  static int _enAnillo(List<Coordenadas> anillo, Coordenadas p) {
    var vueltas = 0;
    for (var i = 0; i < anillo.length - 1; i++) {
      final s1 = anillo[i];
      final s2 = anillo[i + 1];
      final lado = _determineSide(s1, s2, p);
      final dx = s2.lon - s1.lon;
      final dy = s2.lat - s1.lat;
      if (dx * dx + dy * dy < _largoMinimoAlCuadrado) continue;
      if (lado == 0.0 && _enRecuadro(s1, s2, p)) return 0;
      if (lado > 0 && s1.lat <= p.lat && p.lat < s2.lat) {
        vueltas++;
      } else if (lado < 0 && s2.lat <= p.lat && p.lat < s1.lat) {
        vueltas--;
      }
    }
    return vueltas == 0 ? -1 : 1;
  }

  /// `determineSide` de PostGIS, literal (x = lon, y = lat): positivo si [p] está a la izquierda
  /// de [s1]→[s2], negativo a la derecha, 0.0 sobre la recta.
  static double _determineSide(Coordenadas s1, Coordenadas s2, Coordenadas p) =>
      (s2.lon - s1.lon) * (p.lat - s1.lat) - (p.lon - s1.lon) * (s2.lat - s1.lat);

  /// `isOnSegment` de PostGIS: [p] dentro del recuadro del lado, bordes incluidos.
  static bool _enRecuadro(Coordenadas s1, Coordenadas s2, Coordenadas p) {
    final (minX, maxX) = s1.lon > s2.lon ? (s2.lon, s1.lon) : (s1.lon, s2.lon);
    final (minY, maxY) = s1.lat > s2.lat ? (s2.lat, s1.lat) : (s1.lat, s2.lat);
    return p.lon >= minX && p.lon <= maxX && p.lat >= minY && p.lat <= maxY;
  }

  @override
  List<Object?> get props => [poligonos];
}
