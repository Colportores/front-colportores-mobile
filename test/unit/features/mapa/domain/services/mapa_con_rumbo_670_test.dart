// HU-UBI-003 · seguimiento de la ubicación (#670, decisión de Cristian del 05/11, «GPS viejo»): el
// mapa puede girar hacia donde mira la colportora. Dominio puro: los tres modos del botón, la
// proyección con el rumbo de la cámara y los cuadrados de las casas con el mapa girado.
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/domain/services/cuadrados_del_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:test/test.dart';

const _centro = Coordenadas(lat: -34.88761, lon: -56.13024);
const _zoom = 18.0;

/// El punto que queda a ([este], [sur]) dp del [centro], a [zoom], con el norte arriba.
Coordenadas _a(double este, double sur, {Coordenadas centro = _centro, double zoom = _zoom}) {
  final c = ProyeccionMercator.aPixeles(centro, zoom);
  return ProyeccionMercator.aCoordenadas(c.x + este, c.y + sur, zoom);
}

void main() {
  group('ModoSeguimiento', () {
    test('dado el botón, cuando se toca, pasa de libre a seguir, a seguir y girar y vuelve', () {
      expect(ModoSeguimiento.libre.siguiente, ModoSeguimiento.seguir);
      expect(ModoSeguimiento.seguir.siguiente, ModoSeguimiento.seguirYGirar);
      expect(ModoSeguimiento.seguirYGirar.siguiente, ModoSeguimiento.libre);
    });

    test('solo «libre» deja el GPS sin stream y solo «seguir y girar» gira', () {
      expect(ModoSeguimiento.values.where((m) => m.sigue), [
        ModoSeguimiento.seguir,
        ModoSeguimiento.seguirYGirar,
      ]);
      expect(ModoSeguimiento.values.where((m) => m.gira), [ModoSeguimiento.seguirYGirar]);
    });
  });

  group('CamaraMapa · rumbo', () {
    test('por defecto mira al norte y los cambios de centro y zoom conservan el rumbo', () {
      const sinRumbo = CamaraMapa(centro: _centro, zoom: 10);
      expect(sinRumbo.rumbo, 0);

      final girada = sinRumbo.conRumbo(135);
      expect(girada.conZoom(12).rumbo, 135);
      expect(girada.conCentro(_a(10, 10)).rumbo, 135);
      expect(girada, isNot(sinRumbo), reason: 'el rumbo cuenta para la igualdad');
    });

    test('una lectura sin rumbo es distinta de una con rumbo', () {
      const sin = LecturaGps(coordenadas: _centro, precisionMetros: 5);
      const con = LecturaGps(coordenadas: _centro, precisionMetros: 5, rumboGrados: 90);
      expect(sin.rumboGrados, isNull);
      expect(con, isNot(sin));
    });
  });

  group('ProyeccionMercator · aPantalla con el rumbo de la cámara', () {
    const ancho = 400.0;
    const alto = 800.0;

    ({double x, double y}) pantalla(Coordenadas punto, double rumbo) =>
        ProyeccionMercator.aPantalla(
          punto,
          const CamaraMapa(centro: _centro, zoom: _zoom).conRumbo(rumbo),
          ancho: ancho,
          alto: alto,
        );

    test('con el norte arriba es el desplazamiento Mercator de siempre', () {
      final p = pantalla(_a(30, -50), 0);
      expect(p.x, closeTo(ancho / 2 + 30, 1e-6));
      expect(p.y, closeTo(alto / 2 - 50, 1e-6));
    });

    test('con rumbo 90 queda arriba lo que está al este', () {
      final p = pantalla(_a(100, 0), 90);
      expect(p.x, closeTo(ancho / 2, 1e-6));
      expect(p.y, closeTo(alto / 2 - 100, 1e-6));
    });

    test('con rumbo 180 queda arriba lo que está al sur', () {
      final p = pantalla(_a(0, 100), 180);
      expect(p.x, closeTo(ancho / 2, 1e-6));
      expect(p.y, closeTo(alto / 2 - 100, 1e-6));
    });

    test('el centro de la cámara siempre cae en el centro de la vista, gire como gire', () {
      for (final rumbo in [0.0, 37.0, 90.0, 215.0, 359.0]) {
        final p = pantalla(_centro, rumbo);
        expect(p.x, closeTo(ancho / 2, 1e-6), reason: 'rumbo $rumbo');
        expect(p.y, closeTo(alto / 2, 1e-6), reason: 'rumbo $rumbo');
      }
    });

    test('girar no cambia las distancias entre dos puntos', () {
      final a = _a(0, 0);
      final b = _a(60, 80);
      for (final rumbo in [0.0, 45.0, 123.0, 300.0]) {
        final pa = pantalla(a, rumbo);
        final pb = pantalla(b, rumbo);
        expect(math.sqrt(math.pow(pa.x - pb.x, 2) + math.pow(pa.y - pb.y, 2)), closeTo(100, 1e-6));
      }
    });
  });

  group('ProyeccionMercator · centroQueDejaEn', () {
    test('sin rumbo, el centro queda ese desplazamiento por debajo del punto', () {
      // La hoja tapa abajo: el punto se ve 200 dp ARRIBA del centro de la vista.
      final centro = ProyeccionMercator.centroQueDejaEn(
        _centro,
        zoom: _zoom,
        desplazamientoY: -200,
      );
      final c = ProyeccionMercator.aPixeles(centro, _zoom);
      final p = ProyeccionMercator.aPixeles(_centro, _zoom);
      expect(c.x, closeTo(p.x, 1e-6));
      expect(c.y, closeTo(p.y + 200, 1e-6));
    });

    test('con cualquier rumbo, el punto cae donde se pidió en la pantalla', () {
      const ancho = 400.0;
      const alto = 800.0;
      for (final rumbo in [0.0, 30.0, 90.0, 180.0, 271.0, 359.0]) {
        final centro = ProyeccionMercator.centroQueDejaEn(
          _centro,
          zoom: _zoom,
          rumbo: rumbo,
          desplazamientoX: 15,
          desplazamientoY: -200,
        );
        final p = ProyeccionMercator.aPantalla(
          _centro,
          CamaraMapa(centro: centro, zoom: _zoom, rumbo: rumbo),
          ancho: ancho,
          alto: alto,
        );
        expect(p.x, closeTo(ancho / 2 + 15, 1e-5), reason: 'rumbo $rumbo');
        expect(p.y, closeTo(alto / 2 - 200, 1e-5), reason: 'rumbo $rumbo');
      }
    });
  });

  group('CuadradosDelMapa · con el mapa girado', () {
    const ancho = 400.0;
    const alto = 800.0;

    bool entran(List<Coordenadas> casas, double rumbo) => CuadradosDelMapa.entranTodos(
      casas: casas,
      camara: const CamaraMapa(centro: _centro, zoom: _zoom).conRumbo(rumbo),
      ancho: ancho,
      alto: alto,
    );

    test('una casa al este fuera de la vista entra al verse arriba cuando el mapa mira al este', () {
      // Dos casas que se taparían (a 30 dp), 300 dp al este: con el norte arriba están fuera de la
      // vista (el ancho es 400) y no cuentan; con el este arriba están dentro (el alto es 800) y sí.
      final casas = [_a(0, 0), _a(300, 0), _a(300, 30)];
      expect(entran(casas, 0), isTrue, reason: 'las que se tapan no se ven');
      expect(entran(casas, 90), isFalse, reason: 'con el mapa girado se ven y se tapan');
    });

    test('con el mismo juego de casas, girar el mapa no cambia lo que cabe sin taparse', () {
      final casas = [_a(0, 0), _a(80, 0), _a(0, 80)];
      for (final rumbo in [0.0, 33.0, 90.0, 200.0]) {
        expect(entran(casas, rumbo), isTrue, reason: 'rumbo $rumbo');
      }
    });
  });
}
