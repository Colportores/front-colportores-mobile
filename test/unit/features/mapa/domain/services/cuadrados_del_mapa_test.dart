// HU-VIS-005 · vista 39, M·02 (#412), decisión de Cristian del 23/10 («Números casas»): «Cuadrados
// solo si entran». El mapa sigue con puntos y grupos hasta que, acercando, entran todos los
// cuadrados de 40 dp de lo que se ve sin taparse; nunca se tapa una casa con otra.
import 'package:colportores_mobile/features/mapa/domain/services/cuadrados_del_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:flutter_test/flutter_test.dart';

const _centro = Coordenadas(lat: -34.88761, lon: -56.13024);
const _zoom = 18.0;
const _camara = CamaraMapa(centro: _centro, zoom: _zoom);
const _ancho = 400.0;
const _alto = 800.0;

/// La casa que queda a ([dx], [dy]) dp del centro de la vista, a [zoom].
Coordenadas _casaA(double dx, double dy, {double zoom = _zoom}) {
  final c = ProyeccionMercator.aPixeles(_centro, zoom);
  return ProyeccionMercator.aCoordenadas(c.x + dx, c.y + dy, zoom);
}

bool _entran(
  List<Coordenadas> casas, {
  CamaraMapa camara = _camara,
  double ancho = _ancho,
  double alto = _alto,
  double reserva = 0,
}) => CuadradosDelMapa.entranTodos(
  casas: casas,
  camara: camara,
  ancho: ancho,
  alto: alto,
  reservaInferior: reserva,
);

void main() {
  group('CuadradosDelMapa.entranTodos', () {
    test('dada una sola casa a la vista, cuando se pregunta, entonces entra', () {
      expect(_entran([_casaA(0, 0)]), isTrue);
    });

    test('dadas casas con 60 dp entre centros, cuando se pregunta, entonces entran todas', () {
      expect(_entran([_casaA(-60, 0), _casaA(0, 0), _casaA(60, 0), _casaA(0, 60)]), isTrue);
    });

    test('dadas dos casas con 41 dp entre centros (los cuadrados se tocarían), cuando se pregunta, '
        'entonces no entran: nunca se tapa una casa con otra', () {
      expect(_entran([_casaA(0, 0), _casaA(0, 30)]), isFalse);
      expect(_entran([_casaA(0, 0), _casaA(0, 41)]), isFalse);
    });

    test('dadas dos casas a 42 dp (40 más 2 de aire), cuando se pregunta, entonces entran', () {
      expect(_entran([_casaA(0, 0), _casaA(0, 42.5)]), isTrue);
      expect(_entran([_casaA(0, 0), _casaA(42.5, 0)]), isTrue);
    });

    test('dadas dos casas en diagonal cuyos cuadrados no se tocan, cuando se pregunta, entonces '
        'entran; si se tocan por la esquina, no', () {
      expect(_entran([_casaA(0, 0), _casaA(45, 45)]), isTrue);
      expect(_entran([_casaA(0, 0), _casaA(35, 35)]), isFalse);
    });

    test('dadas dos casas en el mismo punto, cuando se pregunta, entonces no entran nunca, '
        'por mucho que se acerque', () {
      for (final zoom in [18.0, 20.0, 22.0]) {
        final casa = _casaA(0, 0, zoom: zoom);
        expect(
          _entran([casa, casa], camara: CamaraMapa(centro: _centro, zoom: zoom)),
          isFalse,
          reason: 'zoom $zoom',
        );
      }
    });

    test('dado un mapa sin casas, cuando se pregunta, entonces no (no hay nada que dibujar)', () {
      expect(_entran(const []), isFalse);
    });

    test('dadas casas que están todas fuera de la vista, cuando se pregunta, entonces no', () {
      expect(_entran([_casaA(900, 0), _casaA(0, 2000)]), isFalse);
    });

    test('dadas casas muy juntas pero fuera de la vista, cuando hay una sola adentro, entonces '
        'solo cuentan las que se ven', () {
      expect(_entran([_casaA(0, 0), _casaA(2000, 0), _casaA(2000, 10)]), isTrue);
    });

    test('dada una casa cortada por el borde de la vista, cuando se pregunta, entonces cuenta: '
        'también tapa a su vecina', () {
      // Su centro está 10 dp afuera: se ve la mitad del cuadrado.
      final afuera = _casaA(_ancho / 2 + 10, 0);
      final vecina = _casaA(_ancho / 2 - 20, 0);

      expect(_entran([afuera, vecina]), isFalse);
      // Si el centro está 25 dp afuera, ya no se ve nada del cuadrado de 40: no cuenta.
      expect(_entran([_casaA(_ancho / 2 + 25, 0), vecina]), isTrue);
    });

    test('dada una casa tapada por la hoja de abajo, cuando se pregunta, entonces no cuenta', () {
      // La hoja tapa 300 dp de los 800: lo que está a más de 100 dp bajo el centro no se ve.
      final tapada = _casaA(0, 200);
      final otra = _casaA(0, 215);

      expect(_entran([otra, tapada]), isFalse);
      expect(_entran([_casaA(0, 0), tapada, otra], reserva: 300), isTrue);
    });

    test('dada la hoja que tapa todo, cuando se pregunta, entonces no', () {
      expect(_entran([_casaA(0, 0)], reserva: 800), isFalse);
      expect(_entran([_casaA(0, 0)], reserva: 900), isFalse);
    });

    test('dado un tamaño de vista inválido, cuando se pregunta, entonces no', () {
      expect(_entran([_casaA(0, 0)], ancho: 0), isFalse);
      expect(_entran([_casaA(0, 0)], alto: -1), isFalse);
      expect(_entran([_casaA(0, 0)], ancho: double.nan), isFalse);
      expect(_entran([_casaA(0, 0)], alto: double.infinity), isFalse);
    });

    test('dadas más casas que cuadrados que caben, cuando se pregunta, entonces no entran, sin '
        'comparar de a pares', () {
      // 40 × 20 = 800 lugares de sobra para 2.000 casas muy juntas en la misma vista.
      final casas = [
        for (var i = 0; i < 2000; i++) _casaA((i % 40) * 9.0 - 180, (i ~/ 40) * 9.0 - 200),
      ];

      expect(_entran(casas), isFalse);
    });

    test('dada una cuadrícula de 8 × 16 casas bien separadas, cuando se pregunta, entonces entran '
        'todas (lista larga)', () {
      final casas = [
        for (var x = 0; x < 8; x++)
          for (var y = 0; y < 16; y++) _casaA(x * 46.0 - 160, y * 46.0 - 350),
      ];

      expect(_entran(casas), isTrue);
    });

    test('dado el mismo conjunto, cuando se acerca, entonces pasa de no entrar a entrar', () {
      // Dos casas a 12 m una de otra: a zoom 17 (0,49 m/dp) son ~24 dp; a zoom 19, ~98 dp.
      const a = _centro;
      final b = Coordenadas(lat: _centro.lat + 12 / 111320, lon: _centro.lon);

      expect(_entran([a, b], camara: const CamaraMapa(centro: _centro, zoom: 17)), isFalse);
      expect(_entran([a, b], camara: const CamaraMapa(centro: _centro, zoom: 19)), isTrue);
    });

    test('dado un conjunto que entra, cuando se aleja, entonces vuelve a no entrar', () {
      const a = _centro;
      final b = Coordenadas(lat: _centro.lat + 12 / 111320, lon: _centro.lon);

      expect(_entran([a, b], camara: const CamaraMapa(centro: _centro, zoom: 19)), isTrue);
      expect(_entran([a, b], camara: const CamaraMapa(centro: _centro, zoom: 16)), isFalse);
    });

    test('dados los mismos datos, cuando se pregunta dos veces, entonces la respuesta es la '
        'misma (función pura)', () {
      final casas = [_casaA(-60, 0), _casaA(60, 0)];

      expect(_entran(casas), _entran(casas));
    });
  });
}
