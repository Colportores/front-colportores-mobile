// Dónde va el nombre de una zona sobre el mapa (#511): siempre adentro de la zona.
import 'package:colportores_mobile/features/mapa/domain/services/punto_rotulo_de_zona.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/geometria_zona.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un anillo `[lon, lat]` a partir de pares `(lon, lat)`.
List<List<double>> _anillo(List<(double, double)> puntos) => [
  for (final (lon, lat) in puntos) [lon, lat],
];

GeometriaZona _poligono(List<List<List<double>>> anillos) =>
    GeometriaZona.desdeGeojson({'type': 'Polygon', 'coordinates': anillos})!;

void main() {
  test('un cuadrado: el centro', () {
    final zona = _poligono([
      _anillo([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)]),
    ]);

    final punto = PuntoRotuloDeZona.de(zona)!;

    expect(punto.lat, closeTo(1, 1e-9));
    expect(punto.lon, closeTo(1, 1e-9));
  });

  test('una L: el punto cae adentro aunque el centro del recuadro quede afuera', () {
    // La L ocupa el recuadro 0..10 x 0..10 menos el cuadrado de arriba a la derecha.
    final zona = _poligono([
      _anillo([(0, 0), (10, 0), (10, 2), (2, 2), (2, 10), (0, 10), (0, 0)]),
    ]);
    expect(
      zona.cubre(const Coordenadas(lat: 5, lon: 5)),
      isFalse,
      reason: 'el centro del recuadro',
    );

    final punto = PuntoRotuloDeZona.de(zona)!;

    expect(zona.cubre(punto), isTrue);
  });

  test('con un hueco en el medio: el punto no cae en el hueco', () {
    final zona = _poligono([
      _anillo([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)]),
      _anillo([(3, 3), (7, 3), (7, 7), (3, 7), (3, 3)]),
    ]);

    final punto = PuntoRotuloDeZona.de(zona)!;

    expect(zona.cubre(punto), isTrue);
  });

  test('varios polígonos: el nombre va en el más grande', () {
    final zona = GeometriaZona.desdeGeojson({
      'type': 'MultiPolygon',
      'coordinates': [
        [
          _anillo([(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)]),
        ],
        [
          _anillo([(10, 10), (20, 10), (20, 20), (10, 20), (10, 10)]),
        ],
      ],
    })!;

    final punto = PuntoRotuloDeZona.de(zona)!;

    expect(punto.lon, closeTo(15, 1e-9));
    expect(punto.lat, closeTo(15, 1e-9));
  });

  test('una forma sin área no tiene punto: la zona se dibuja igual, sin nombre', () {
    final zona = _poligono([
      _anillo([(0, 0), (5, 0), (10, 0), (0, 0)]),
    ]);

    expect(PuntoRotuloDeZona.de(zona), isNull);
  });
}
