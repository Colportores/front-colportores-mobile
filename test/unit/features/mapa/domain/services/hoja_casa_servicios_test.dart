// Las dos reglas puras de la hoja de la casa (vista 39): cuándo avisar «Estás a N m de esta casa»
// (E·05, desde 100 m, decisión de Cristian del 23/10) y cuándo hay que elegir entre varias
// ubicaciones del mismo punto (E·06, sin número nuevo: 44 dp y el zoom máximo).
import 'package:colportores_mobile/features/mapa/domain/services/cercania_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ubicaciones_en_el_punto.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

void main() {
  group('CercaniaDeLaCasa', () {
    test('el umbral es el mismo número que el de duplicados y el de la Lista', () {
      expect(
        CercaniaDeLaCasa.umbralLejosMetros,
        CriterioDuplicadoUbicacion.radioMismaDireccionMetros,
      );
      expect(CercaniaDeLaCasa.umbralLejosMetros, 100);
    });

    test('a 99,9 m no está lejos y a 100 m sí (desde 100 m)', () {
      expect(CercaniaDeLaCasa.estaLejos(99.9), isFalse);
      expect(CercaniaDeLaCasa.estaLejos(100), isTrue);
      expect(CercaniaDeLaCasa.estaLejos(650), isTrue);
    });

    test('sin posición (null) o con una distancia que no existe no está lejos', () {
      expect(CercaniaDeLaCasa.estaLejos(null), isFalse);
      expect(CercaniaDeLaCasa.estaLejos(double.nan), isFalse);
      expect(CercaniaDeLaCasa.estaLejos(double.infinity), isFalse);
      expect(CercaniaDeLaCasa.estaLejos(0), isFalse);
    });
  });

  group('UbicacionesEnElPunto', () {
    final zoomMaximo = ProyeccionMercator.zoomDeFlutterMap(19);
    const base = Coordenadas(lat: -34.9, lon: -56.16);

    Coordenadas alNorte(double metros) =>
        Coordenadas(lat: base.lat + metros / 111320, lon: base.lon);

    List<({String id, Coordenadas coordenadas})> puntos(Map<String, double> metrosAlNorte) => [
      for (final e in metrosAlNorte.entries) (id: e.key, coordenadas: alNorte(e.value)),
    ];

    List<String> elegibles(String tocada, Map<String, double> puntosAlNorte, {double? zoom}) =>
        UbicacionesEnElPunto.elegibles(
          tocada: tocada,
          todas: puntos(puntosAlNorte),
          zoom: zoom ?? zoomMaximo,
          zoomMaximo: zoomMaximo,
        );

    test('con el zoom máximo, tres casas en el mismo punto piden elegir, la tocada primero', () {
      expect(elegibles('u-2', {'u-1': 0, 'u-2': 0, 'u-3': 0}), ['u-2', 'u-1', 'u-3']);
    });

    test('van de la más cercana al toque a la más lejana', () {
      // A zoom máximo 44 dp son unos 10,8 m.
      expect(elegibles('u-1', {'u-1': 0, 'u-2': 8, 'u-3': 3}), ['u-1', 'u-3', 'u-2']);
    });

    test('una a más de 44 dp no entra en la elección', () {
      expect(elegibles('u-1', {'u-1': 0, 'u-2': 5, 'u-3': 40}), ['u-1', 'u-2']);
    });

    test('una sola dentro de los 44 dp no pide elegir', () {
      expect(elegibles('u-1', {'u-1': 0, 'u-2': 40}), isEmpty);
      expect(elegibles('u-1', {'u-1': 0}), isEmpty);
    });

    test(
      'antes del zoom máximo se abre la más cercana: no se pide elegir (se acerca con los dedos)',
      () {
        expect(elegibles('u-1', {'u-1': 0, 'u-2': 0}, zoom: zoomMaximo - 1), isEmpty);
        expect(elegibles('u-1', {'u-1': 0, 'u-2': 0}, zoom: zoomMaximo - 0.5), isEmpty);
      },
    );

    test('un zoom a una milésima del máximo (la vista no vuelve exacto) cuenta como el máximo', () {
      expect(elegibles('u-1', {'u-1': 0, 'u-2': 0}, zoom: zoomMaximo - 0.01), ['u-1', 'u-2']);
    });

    test('si la tocada no está entre las que pinta el mapa, no hay nada que elegir', () {
      expect(elegibles('u-9', {'u-1': 0, 'u-2': 0}), isEmpty);
    });

    test('con un zoom que no existe (NaN) no pide elegir', () {
      expect(elegibles('u-1', {'u-1': 0, 'u-2': 0}, zoom: double.nan), isEmpty);
    });

    test('a igual distancia respeta el orden en que llegaron', () {
      expect(elegibles('u-1', {'u-1': 0, 'u-4': 0, 'u-2': 0, 'u-3': 0}), [
        'u-1',
        'u-4',
        'u-2',
        'u-3',
      ]);
    });
  });
}
