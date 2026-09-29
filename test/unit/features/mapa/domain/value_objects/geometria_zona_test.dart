// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/geometria_zona.dart';
import 'package:test/test.dart';

/// Un punto a partir de `[lon, lat]`, el orden de GeoJSON.
Coordenadas _p(double lon, double lat) => Coordenadas(lat: lat, lon: lon);

/// Un `Polygon` con [anillos] de puntos `[lon, lat]`.
Map<String, Object?> _poligono(List<List<List<double>>> anillos) => {
  'type': 'Polygon',
  'coordinates': anillos,
};

GeometriaZona _geometria(Object? geojson) => GeometriaZona.desdeGeojson(geojson)!;

void main() {
  final cuadrado = _geometria(
    _poligono([
      [
        [0, 0],
        [10, 0],
        [10, 10],
        [0, 10],
        [0, 0],
      ],
    ]),
  );

  group('GeometriaZona.cubre', () {
    test('dado un punto adentro del polígono, lo cubre', () {
      expect(cuadrado.cubre(_p(5, 5)), isTrue);
    });

    test('dado un punto afuera del polígono, no lo cubre', () {
      expect(cuadrado.cubre(_p(15, 5)), isFalse);
      expect(cuadrado.cubre(_p(5, -0.000001)), isFalse);
    });

    test(
      'dado un punto sobre el borde o en un vértice, lo cubre (el borde cuenta como adentro)',
      () {
        expect(cuadrado.cubre(_p(5, 0)), isTrue);
        expect(cuadrado.cubre(_p(10, 7.5)), isTrue);
        expect(cuadrado.cubre(_p(0, 0)), isTrue);
        expect(cuadrado.cubre(_p(10, 10)), isTrue);
      },
    );

    test('dado un punto sobre un lado diagonal, lo cubre', () {
      // 3.3 + 6.7 da exactamente 10 en double: el punto está sobre el lado de (10, 0) a (0, 10).
      final triangulo = _geometria(
        _poligono([
          [
            [0, 0],
            [10, 0],
            [0, 10],
          ],
        ]),
      );

      expect(triangulo.cubre(_p(3.3, 6.7)), isTrue);
      expect(triangulo.cubre(_p(3.3, 6.71)), isFalse);
    });

    test(
      'dado un punto que el redondeo pone sobre un lado pero está apenas afuera, no lo cubre',
      () {
        // Con double, la orientación de (0.3, 0.1) respecto del lado (3, 1) → (0, 0) da 0; con la
        // cuenta exacta, el punto queda arriba de la recta: afuera del triángulo de abajo y adentro
        // del de arriba. Lo mismo que decide ST_Covers.
        final abajo = _geometria(
          _poligono([
            [
              [0, 0],
              [3, 0],
              [3, 1],
            ],
          ]),
        );
        final arriba = _geometria(
          _poligono([
            [
              [0, 0],
              [3, 1],
              [0, 1],
            ],
          ]),
        );

        expect(abajo.cubre(_p(0.3, 0.1)), isFalse);
        expect(arriba.cubre(_p(0.3, 0.1)), isTrue);
      },
    );

    group('dado un polígono cóncavo en L', () {
      final ele = _geometria(
        _poligono([
          [
            [0, 0],
            [10, 0],
            [10, 4],
            [4, 4],
            [4, 10],
            [0, 10],
            [0, 0],
          ],
        ]),
      );

      test('un punto en el hueco de la L queda afuera', () {
        expect(ele.cubre(_p(7, 7)), isFalse);
      });

      test('un punto en cada brazo de la L queda adentro', () {
        expect(ele.cubre(_p(2, 8)), isTrue);
        expect(ele.cubre(_p(8, 2)), isTrue);
      });

      test('el vértice de la esquina interior y los lados del hueco son borde', () {
        expect(ele.cubre(_p(4, 4)), isTrue);
        expect(ele.cubre(_p(7, 4)), isTrue);
        expect(ele.cubre(_p(4, 7)), isTrue);
      });
    });

    group('dado un polígono con un hueco', () {
      final conHueco = _geometria(
        _poligono([
          [
            [0, 0],
            [10, 0],
            [10, 10],
            [0, 10],
          ],
          [
            [3, 3],
            [7, 3],
            [7, 7],
            [3, 7],
          ],
        ]),
      );

      test('un punto dentro del hueco queda afuera', () {
        expect(conHueco.cubre(_p(5, 5)), isFalse);
      });

      test('un punto entre el borde exterior y el hueco queda adentro', () {
        expect(conHueco.cubre(_p(1, 1)), isTrue);
      });

      test('el borde del hueco es borde del polígono', () {
        expect(conHueco.cubre(_p(3, 5)), isTrue);
      });
    });

    test('dado un MultiPolygon, cubre los puntos de cualquiera de sus polígonos y no los de entre '
        'medio', () {
      final dos = _geometria({
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [
              [0, 0],
              [1, 0],
              [1, 1],
              [0, 1],
            ],
          ],
          [
            [
              [5, 5],
              [6, 5],
              [6, 6],
              [5, 6],
            ],
          ],
        ],
      });

      expect(dos.cubre(_p(0.5, 0.5)), isTrue);
      expect(dos.cubre(_p(5.5, 5.5)), isTrue);
      expect(dos.cubre(_p(6, 5.5)), isTrue);
      expect(dos.cubre(_p(3, 3)), isFalse);
    });

    test('con las coordenadas en [lon, lat]: un punto con lat y lon invertidas queda afuera', () {
      final alargado = _geometria(
        _poligono([
          [
            [-56.2, -34.95],
            [-56.1, -34.95],
            [-56.1, -34.85],
            [-56.2, -34.85],
          ],
        ]),
      );

      expect(alargado.cubre(const Coordenadas(lat: -34.9, lon: -56.15)), isTrue);
      expect(alargado.cubre(const Coordenadas(lat: -56.15, lon: -34.9)), isFalse);
    });
  });

  group('GeometriaZona.desdeGeojson', () {
    test('acepta números enteros y decimales y el anillo sin cerrar', () {
      final abierto = _geometria(
        _poligono([
          [
            [0, 0],
            [10, 0],
            [10, 10],
          ],
        ]),
      );

      expect(abierto.poligonos.single.single, hasLength(3));
      expect(abierto.cubre(_p(9, 1)), isTrue);
    });

    test('dado algo que no es un Polygon ni un MultiPolygon bien formado, devuelve null', () {
      final invalidos = <Object?>[
        null,
        'Polygon',
        <String, Object?>{
          'type': 'Point',
          'coordinates': <double>[0, 0],
        },
        <String, Object?>{'type': 'Polygon'},
        <String, Object?>{'type': 'Polygon', 'coordinates': <Object?>[]},
        _poligono([
          [
            [0, 0],
            [1, 1],
          ],
        ]),
        <String, Object?>{
          'type': 'Polygon',
          'coordinates': [
            [
              [0, 0],
              [1, 0],
              ['uno', 1],
            ],
          ],
        },
        <String, Object?>{
          'type': 'Polygon',
          'coordinates': [
            [
              [0, 0],
              [1, 0],
              [1],
            ],
          ],
        },
        <String, Object?>{'type': 'MultiPolygon', 'coordinates': 'no'},
        <String, Object?>{'type': 'MultiPolygon', 'coordinates': <Object?>[]},
        <String, Object?>{
          'type': 'MultiPolygon',
          'coordinates': [<Object?>[]],
        },
      ];

      for (final geojson in invalidos) {
        expect(GeometriaZona.desdeGeojson(geojson), isNull, reason: '$geojson');
      }
    });

    test('dos geometrías con los mismos puntos son iguales; con otros, no', () {
      final otra = _geometria(
        _poligono([
          [
            [0, 0],
            [10, 0],
            [10, 10],
            [0, 10],
            [0, 0],
          ],
        ]),
      );
      final distinta = _geometria(
        _poligono([
          [
            [0, 0],
            [9, 0],
            [9, 9],
          ],
        ]),
      );

      expect(otra, cuadrado);
      expect(otra.hashCode, cuadrado.hashCode);
      expect(distinta, isNot(cuadrado));
    });
  });
}
