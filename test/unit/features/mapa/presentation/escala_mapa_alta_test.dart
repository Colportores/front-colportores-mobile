// La escala de zoom del alta de ubicación (#288). El alta se diseñó con `flutter_map` (#267: teselas
// de 256 px, el mundo mide `256 · 2^z`) y se dibuja con MapLibre (teselas de 512 px: `512 · 2^z`).
// El mismo número de zoom se ve al doble de cerca en MapLibre: Uruguay no entraba en la pantalla del
// artboard 03A · 02 y el radio de ±85 m del 03A · 03 la llenaba de borde a borde.
//
// Estos tests miden, en dp y en metros, lo que ve el colportor, con los números de #267 escritos acá
// como literales: si alguien vuelve a poner un zoom de `flutter_map` tal cual, fallan.
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:flutter_test/flutter_test.dart';

/// El teléfono chico del diseño: ancho de 360 dp y unos 400 dp de mapa sobre la hoja.
const _ancho = 360.0;
const _alto = 400.0;

const _montevideo = Coordenadas(lat: -34.88761, lon: -56.13024);

/// Los límites de Uruguay (continente).
const _oeste = -58.44;
const _este = -53.07;
const _sur = -35.0;
const _norte = -30.1;

void main() {
  group('los zoom del alta mantienen el encuadre de #267', () {
    test('el mundo mide lo mismo que en flutter_map con los números de #267 (256 · 2^z)', () {
      double enFlutterMap(double zoom) => 256 * math.pow(2, zoom).toDouble();

      expect(ProyeccionMercator.tamanoMundo(MapaAlta.zoomPais), closeTo(enFlutterMap(6.5), 1e-6));
      expect(ProyeccionMercator.tamanoMundo(MapaAlta.zoomCalle), closeTo(enFlutterMap(17), 1e-6));
      expect(ProyeccionMercator.tamanoMundo(MapaAlta.zoomMinimo), closeTo(enFlutterMap(3), 1e-6));
      expect(ProyeccionMercator.tamanoMundo(MapaAlta.zoomMaximo), closeTo(enFlutterMap(19), 1e-6));
      expect(
        ProyeccionMercator.tamanoMundo(MapaAlta.zoomMaximoVistaPrevia),
        closeTo(enFlutterMap(18), 1e-6),
      );
    });

    test('los valores en la escala de MapLibre, a la vista: un nivel menos que flutter_map', () {
      expect(MapaAlta.zoomPais, 5.5);
      expect(MapaAlta.zoomCalle, 16);
      expect(MapaAlta.zoomMinimo, 2);
      expect(MapaAlta.zoomMaximo, 18);
      expect(MapaAlta.zoomMaximoVistaPrevia, 17);
    });

    test('sin GPS (03A · 02) Uruguay entero entra en el mapa, y llena buena parte', () {
      final area = ProyeccionMercator.areaVisible(
        CamaraMapa(centro: MapaAlta.centroPorDefecto, zoom: MapaAlta.zoomPais),
        ancho: _ancho,
        alto: _alto,
      );

      expect(area.oeste, lessThanOrEqualTo(_oeste));
      expect(area.este, greaterThanOrEqualTo(_este));
      expect(area.sur, lessThanOrEqualTo(_sur));
      expect(area.norte, greaterThanOrEqualTo(_norte));

      // No queda perdido en el medio: ocupa más de la mitad del ancho y no se sale de la pantalla.
      final suroeste = ProyeccionMercator.aPixeles(const Coordenadas(lat: _sur, lon: _oeste), 0);
      final noreste = ProyeccionMercator.aPixeles(const Coordenadas(lat: _norte, lon: _este), 0);
      final escala =
          ProyeccionMercator.tamanoMundo(MapaAlta.zoomPais) / ProyeccionMercator.tamanoMundo(0);
      final anchoUruguay = (noreste.x - suroeste.x) * escala;
      final altoUruguay = (suroeste.y - noreste.y) * escala;
      expect(anchoUruguay, inInclusiveRange(_ancho / 2, _ancho));
      expect(altoUruguay, inInclusiveRange(_alto / 2, _alto));
    });

    test('a zoom de calle el radio de ±85 m (03A · 03) mide unos 87 dp y no llena la pantalla', () {
      final metrosPorDp = ProyeccionMercator.metrosPorPixel(_montevideo.lat, MapaAlta.zoomCalle);
      final radioDp = 85 / metrosPorDp;

      expect(radioDp, inInclusiveRange(80, 95));
      expect(radioDp * 2, lessThan(_ancho * 0.6), reason: 'el círculo entero cabe holgado');
    });

    test('a zoom de calle se ven unos 350 m de ancho, como en #267', () {
      final metrosPorDp = ProyeccionMercator.metrosPorPixel(_montevideo.lat, MapaAlta.zoomCalle);

      expect(metrosPorDp * _ancho, closeTo(353, 5));
    });

    test('la vista previa de duplicados no se acerca a menos de unos 0,49 m por dp', () {
      final metrosPorDp = ProyeccionMercator.metrosPorPixel(
        _montevideo.lat,
        MapaAlta.zoomMaximoVistaPrevia,
      );
      expect(metrosPorDp, closeTo(0.49, 0.01));

      // Dos ubicaciones a 4 m (el caso «a pocos metros») se ven a unos 8 dp, no a 16.
      const cerca = Coordenadas(lat: -34.88761, lon: -56.130196);
      final camara = ProyeccionMercator.camaraQueAjusta(
        [_montevideo, cerca],
        ancho: _ancho,
        alto: 150,
        margen: 40,
        zoomMaximo: MapaAlta.zoomMaximoVistaPrevia,
      );
      expect(camara.zoom, MapaAlta.zoomMaximoVistaPrevia);
      final separacion = ProyeccionMercator.distanciaPixeles(_montevideo, cerca, camara.zoom);
      expect(separacion, inInclusiveRange(6, 12));
    });

    test('el zoom mínimo deja ver medio continente y el máximo, una cuadra', () {
      // Con 360 dp de ancho, el mínimo muestra casi 6000 km (medio continente) y el máximo, unos 90 m.
      final enElMinimo = ProyeccionMercator.metrosPorPixel(_montevideo.lat, MapaAlta.zoomMinimo);
      final enElMaximo = ProyeccionMercator.metrosPorPixel(_montevideo.lat, MapaAlta.zoomMaximo);

      expect(enElMinimo * _ancho / 1000, inInclusiveRange(5000, 6500));
      expect(enElMaximo * _ancho, inInclusiveRange(80, 100));
      expect(MapaAlta.zoomMinimo, lessThan(MapaAlta.zoomPais));
      expect(MapaAlta.zoomPais, lessThan(MapaAlta.zoomCalle));
      expect(MapaAlta.zoomCalle, lessThan(MapaAlta.zoomMaximo));
    });
  });
}
