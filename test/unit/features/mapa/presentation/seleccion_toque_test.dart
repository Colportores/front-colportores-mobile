// Qué punto o grupo del mapa se tocó (M3 del #288): un área de 48 dp alrededor del dedo y, de lo que
// cae adentro, lo más cercano al toque.
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/seleccion_toque.dart';
import 'package:flutter_test/flutter_test.dart';

const _toque = Coordenadas(lat: -34.9000, lon: -56.1500);

Map<String, dynamic> _punto(String id, double lat, double lon) => {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [lon, lat],
  },
  'properties': {'id': id},
};

void main() {
  group('SeleccionToque.area', () {
    test('es un cuadrado de 48 dp centrado en el toque', () {
      final area = SeleccionToque.area(const math.Point(100, 200), unidadesPorDp: 1);

      expect(area.width, 48);
      expect(area.height, 48);
      expect(area.center.dx, 100);
      expect(area.center.dy, 200);
    });

    test('en Android la vista habla en píxeles nativos: 48 dp son 48 × la densidad', () {
      final area = SeleccionToque.area(const math.Point(300, 600), unidadesPorDp: 2.75);

      expect(area.width, closeTo(48 * 2.75, 1e-9));
      expect(area.height, closeTo(48 * 2.75, 1e-9));
      expect(area.center.dx, 300);
      expect(area.center.dy, 600);
    });

    test('el lado mínimo del objetivo táctil es el de Material (48 dp)', () {
      expect(SeleccionToque.ladoDp, 48);
    });
  });

  group('SeleccionToque.masCercano', () {
    test('de varios, gana el que está más cerca del dedo, no el primero de la lista', () {
      final lejos = _punto('lejos', -34.9001, -56.1500);
      final cerca = _punto('cerca', -34.90001, -56.1500);

      final elegido = SeleccionToque.masCercano([lejos, cerca], _toque);

      expect(elegido, same(cerca));
    });

    test('mide en los dos ejes: un vecino al este puede ser más cercano que uno al norte', () {
      final norte = _punto('norte', -34.89990, -56.1500);
      final este = _punto('este', -34.9000, -56.14995);

      expect(SeleccionToque.masCercano([norte, este], _toque), same(este));
    });

    test('a igual distancia gana el primero (el de la capa de más arriba)', () {
      // Coordenadas exactas en binario: la distancia a los dos es idéntica, sin redondeos.
      const centro = Coordenadas(lat: -35, lon: -56);
      final a = _punto('a', -35.25, -56);
      final b = _punto('b', -34.75, -56);

      expect(SeleccionToque.masCercano([a, b], centro), same(a));
      expect(SeleccionToque.masCercano([b, a], centro), same(b));
    });

    test('uno solo es el elegido', () {
      final unico = _punto('u', -34.9002, -56.1502);

      expect(SeleccionToque.masCercano([unico], _toque), same(unico));
    });

    test('sin nada, no hay elegido', () {
      expect(SeleccionToque.masCercano(const [], _toque), isNull);
    });

    test('lo que no es un punto con coordenadas se saltea, no revienta', () {
      final bueno = _punto('bueno', -34.9005, -56.1500);
      final raros = <Object?>[
        null,
        'texto',
        42,
        <String, dynamic>{},
        {'geometry': 'no es un mapa'},
        {
          'geometry': {'coordinates': 'tampoco'},
        },
        {
          'geometry': {
            'coordinates': [1.0],
          },
        },
        {
          'geometry': {
            'coordinates': ['a', 'b'],
          },
        },
      ];

      expect(SeleccionToque.masCercano([...raros, bueno], _toque), same(bueno));
      expect(SeleccionToque.masCercano(raros, _toque), isNull);
    });

    test('un grupo (un Feature más) compite por distancia como cualquier punto', () {
      final grupo = {
        ..._punto('g', -34.90001, -56.1500),
        'properties': {'cluster': true, 'cluster_id': 3, 'point_count': 8},
      };
      final punto = _punto('p', -34.9002, -56.1500);

      expect(SeleccionToque.masCercano([punto, grupo], _toque), same(grupo));
    });

    test('las coordenadas enteras (un número sin decimales) también valen', () {
      final entero = {
        'geometry': {
          'coordinates': [-56, -35],
        },
      };

      expect(
        SeleccionToque.masCercano([entero], const Coordenadas(lat: -35, lon: -56)),
        same(entero),
      );
    });
  });
}
