// Test de dominio: Dart puro (HU-UBI-003, #286): la proyección Web Mercator de MapLibre, la cámara
// que ajusta un conjunto de puntos y el área visible.
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:test/test.dart';

void main() {
  const montevideo = Coordenadas(lat: -34.88761, lon: -56.13024);

  group('ProyeccionMercator · píxeles', () {
    test('el mundo mide 512 · 2^zoom píxeles', () {
      expect(ProyeccionMercator.tamanoMundo(0), 512);
      expect(ProyeccionMercator.tamanoMundo(1), 1024);
      expect(ProyeccionMercator.tamanoMundo(17), 512 * 131072);
    });

    test('(0, 0) cae en el centro del mundo y el noroeste en la esquina', () {
      final centro = ProyeccionMercator.aPixeles(const Coordenadas(lat: 0, lon: 0), 0);
      expect(centro.x, closeTo(256, 1e-9));
      expect(centro.y, closeTo(256, 1e-9));

      final esquina = ProyeccionMercator.aPixeles(
        const Coordenadas(lat: ProyeccionMercator.latitudMaxima, lon: -180),
        0,
      );
      expect(esquina.x, closeTo(0, 1e-9));
      expect(esquina.y, closeTo(0, 1e-6));
    });

    test('más allá de la latitud máxima se recorta en vez de estirarse al infinito', () {
      final polo = ProyeccionMercator.aPixeles(const Coordenadas(lat: 90, lon: 0), 3);
      final tope = ProyeccionMercator.aPixeles(
        const Coordenadas(lat: ProyeccionMercator.latitudMaxima, lon: 0),
        3,
      );
      expect(polo.y.isFinite, isTrue);
      expect(polo.y, tope.y);
    });

    test('aCoordenadas es la inversa de aPixeles', () {
      for (final zoom in [0.0, 6.5, 17.0, 19.0]) {
        final p = ProyeccionMercator.aPixeles(montevideo, zoom);
        final vuelta = ProyeccionMercator.aCoordenadas(p.x, p.y, zoom);
        expect(vuelta.lat, closeTo(montevideo.lat, 1e-9));
        expect(vuelta.lon, closeTo(montevideo.lon, 1e-9));
      }
    });

    test('la distancia en píxeles se duplica con cada zoom', () {
      const otro = Coordenadas(lat: -34.88761, lon: -56.13);
      final z16 = ProyeccionMercator.distanciaPixeles(montevideo, otro, 16);
      final z17 = ProyeccionMercator.distanciaPixeles(montevideo, otro, 17);
      expect(z17, closeTo(z16 * 2, 1e-6));
      expect(ProyeccionMercator.distanciaPixeles(montevideo, montevideo, 17), 0);
    });

    test('a zoom 17 un píxel son unos 0,49 m en Montevideo', () {
      const unPixelAlEste = Coordenadas(lat: -34.88761, lon: -56.13024 + 360 / (512 * 131072));
      final metros = montevideo.distanciaMetrosA(unPixelAlEste);
      expect(metros, closeTo(0.49, 0.02));
    });
  });

  group('ProyeccionMercator · escala de flutter_map y metros por píxel', () {
    test('un zoom de flutter_map (teselas de 256 px) es uno menos en MapLibre (512 px)', () {
      for (final z in [3.0, 6.5, 17.0, 19.0]) {
        // Mismo mundo en píxeles: `256 · 2^z` en flutter_map, `512 · 2^(z − 1)` acá.
        expect(
          ProyeccionMercator.tamanoMundo(ProyeccionMercator.zoomDeFlutterMap(z)),
          closeTo(256 * math.pow(2, z), 1e-6),
        );
      }
      expect(ProyeccionMercator.zoomDeFlutterMap(17), 16);
      expect(ProyeccionMercator.zoomDeFlutterMap(6.5), 5.5);
    });

    test('a zoom 17 un píxel son unos 0,49 m en Montevideo y 0,60 m en el ecuador', () {
      expect(ProyeccionMercator.metrosPorPixel(montevideo.lat, 17), closeTo(0.49, 0.005));
      expect(ProyeccionMercator.metrosPorPixel(0, 17), closeTo(0.5972, 0.0005));
    });

    test('cada nivel de zoom divide por dos los metros por píxel', () {
      final z16 = ProyeccionMercator.metrosPorPixel(montevideo.lat, 16);
      final z17 = ProyeccionMercator.metrosPorPixel(montevideo.lat, 17);
      expect(z16, closeTo(2 * z17, 1e-9));
    });

    test('coincide con lo que miden dos puntos conocidos en píxeles', () {
      // 0,001° de latitud son unos 111,3 m en la esfera de Web Mercator.
      const otro = Coordenadas(lat: -34.88661, lon: -56.13024);
      final px = ProyeccionMercator.distanciaPixeles(montevideo, otro, 17);
      final metros = px * ProyeccionMercator.metrosPorPixel(montevideo.lat, 17);

      expect(metros, closeTo(111.3, 0.3));
    });

    test('más allá de la latitud máxima no se va al infinito ni da cero', () {
      final polo = ProyeccionMercator.metrosPorPixel(90, 3);

      expect(polo.isFinite, isTrue);
      expect(polo, greaterThan(0));
    });
  });

  group('ProyeccionMercator · área visible', () {
    test('un teléfono a zoom 17 ve un recuadro de unos 175 m de ancho, centrado', () {
      const camara = CamaraMapa(centro: montevideo, zoom: 17);
      final area = ProyeccionMercator.areaVisible(camara, ancho: 360, alto: 640);

      expect(area.esValida, isTrue);
      expect(area.contiene(montevideo), isTrue);
      expect((area.norte + area.sur) / 2, closeTo(montevideo.lat, 1e-4));
      expect((area.este + area.oeste) / 2, closeTo(montevideo.lon, 1e-9));
      final ancho = Coordenadas(
        lat: montevideo.lat,
        lon: area.oeste,
      ).distanciaMetrosA(Coordenadas(lat: montevideo.lat, lon: area.este));
      expect(ancho, closeTo(360 * 0.49, 3));
    });

    test('más grande que el mundo, a lo ancho abarca el mundo entero', () {
      const camara = CamaraMapa(centro: Coordenadas(lat: 0, lon: 0), zoom: 0);
      final area = ProyeccionMercator.areaVisible(camara, ancho: 1000, alto: 1000);

      expect(area.oeste, -180);
      expect(area.este, 180);
      expect(area.sur, closeTo(-ProyeccionMercator.latitudMaxima, 1e-6));
      expect(area.norte, closeTo(ProyeccionMercator.latitudMaxima, 1e-6));
      expect(area.esValida, isTrue);
    });

    test('cruzando el antimeridiano el oeste queda al este del este', () {
      const camara = CamaraMapa(centro: Coordenadas(lat: 0, lon: 179.999), zoom: 10);
      final area = ProyeccionMercator.areaVisible(camara, ancho: 400, alto: 400);

      expect(area.cruzaAntimeridiano, isTrue);
      expect(area.contiene(const Coordenadas(lat: 0, lon: 179.999)), isTrue);
      expect(area.contiene(const Coordenadas(lat: 0, lon: -179.999)), isTrue);
      expect(area.contiene(const Coordenadas(lat: 0, lon: 0)), isFalse);
    });

    test('un borde justo en +180 se conserva en +180', () {
      // A zoom 0 el mundo mide 512 px: el centro en lon 90 (x = 384) con 256 px de ancho llega
      // exacto al borde este del mundo.
      final area = ProyeccionMercator.areaVisible(
        const CamaraMapa(centro: Coordenadas(lat: 0, lon: 90), zoom: 0),
        ancho: 256,
        alto: 256,
      );

      expect(area.oeste, 0);
      expect(area.este, 180);
      expect(area.cruzaAntimeridiano, isFalse);
    });

    test('cerca del polo el área se recorta al borde del mapa', () {
      const camara = CamaraMapa(centro: Coordenadas(lat: 85, lon: 0), zoom: 3);
      final area = ProyeccionMercator.areaVisible(camara, ancho: 400, alto: 600);

      expect(area.norte, closeTo(ProyeccionMercator.latitudMaxima, 1e-6));
      expect(area.esValida, isTrue);
    });
  });

  group('ProyeccionMercator · camaraQueAjusta', () {
    test('sin puntos es un error de programación', () {
      expect(
        () => ProyeccionMercator.camaraQueAjusta(const [], ancho: 300, alto: 150),
        throwsArgumentError,
      );
    });

    test('un solo punto es ese punto al zoom máximo', () {
      final camara = ProyeccionMercator.camaraQueAjusta(
        const [montevideo],
        ancho: 300,
        alto: 150,
        margen: 40,
      );

      expect(camara.centro.lat, closeTo(montevideo.lat, 1e-9));
      expect(camara.centro.lon, closeTo(montevideo.lon, 1e-9));
      expect(camara.zoom, 18);
    });

    test('varios puntos en el mismo lugar también', () {
      final camara = ProyeccionMercator.camaraQueAjusta(
        const [montevideo, montevideo],
        ancho: 300,
        alto: 150,
        zoomMaximo: 16,
      );

      expect(camara.zoom, 16);
    });

    test('dos puntos quedan adentro de la vista con el margen libre en cada borde', () {
      const norte = Coordenadas(lat: -34.8870, lon: -56.1302);
      const sur = Coordenadas(lat: -34.8890, lon: -56.1302);
      final camara = ProyeccionMercator.camaraQueAjusta(
        const [norte, sur],
        ancho: 300,
        alto: 150,
        margen: 40,
      );

      final a = ProyeccionMercator.aPixeles(norte, camara.zoom);
      final b = ProyeccionMercator.aPixeles(sur, camara.zoom);
      final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
      expect((a.y - centro.y).abs(), lessThanOrEqualTo(150 / 2 - 40 + 1e-6));
      expect((b.y - centro.y).abs(), lessThanOrEqualTo(150 / 2 - 40 + 1e-6));
      // El zoom es el más grande que entra: el alto manda (los puntos están alineados).
      expect((b.y - a.y).abs(), closeTo(150 - 2 * 40, 1e-6));
      expect(camara.zoom, lessThan(18));
    });

    test('puntos separados a lo ancho los ajusta el ancho', () {
      const oeste = Coordenadas(lat: -34.88, lon: -56.14);
      const este = Coordenadas(lat: -34.88, lon: -56.12);
      final camara = ProyeccionMercator.camaraQueAjusta(
        const [oeste, este],
        ancho: 300,
        alto: 600,
        margen: 20,
      );

      final a = ProyeccionMercator.aPixeles(oeste, camara.zoom);
      final b = ProyeccionMercator.aPixeles(este, camara.zoom);
      expect((b.x - a.x).abs(), closeTo(300 - 2 * 20, 1e-6));
    });

    test('con un margen mayor que la vista no se rompe (queda un píxel libre)', () {
      final camara = ProyeccionMercator.camaraQueAjusta(
        const [Coordenadas(lat: -34.88, lon: -56.14), Coordenadas(lat: -34.89, lon: -56.12)],
        ancho: 50,
        alto: 50,
        margen: 100,
      );

      expect(camara.zoom.isFinite, isTrue);
      expect(camara.zoom, greaterThanOrEqualTo(0));
    });

    test('puntos en lados opuestos del mundo dan zoom 0, nunca negativo', () {
      final camara = ProyeccionMercator.camaraQueAjusta(
        const [Coordenadas(lat: 60, lon: -170), Coordenadas(lat: -60, lon: 170)],
        ancho: 100,
        alto: 100,
      );

      expect(camara.zoom, 0);
      expect(math.pow(2, camara.zoom), 1);
    });
  });

  group('CamaraMapa', () {
    const camara = CamaraMapa(centro: montevideo, zoom: 12);

    test('conCentro y conZoom cambian solo lo suyo', () {
      const otro = Coordenadas(lat: 1, lon: 2);
      expect(camara.conCentro(otro), const CamaraMapa(centro: otro, zoom: 12));
      expect(camara.conZoom(15), const CamaraMapa(centro: montevideo, zoom: 15));
    });

    test('es un valor: igual por contenido', () {
      expect(camara, const CamaraMapa(centro: montevideo, zoom: 12));
      expect(camara, isNot(const CamaraMapa(centro: montevideo, zoom: 13)));
    });
  });
}
