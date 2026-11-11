// Cómo se ve una zona sobre el mapa (#511): el color del borde con contraste (AA), el nombre y lo que
// se le dice al lector de pantalla.
import 'package:colportores_mobile/features/mapa/domain/entities/zona_del_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/geometria_zona.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_zonas_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ZonaDelMapa _zona(String id, String nombre, {bool propia = false, String? color}) => ZonaDelMapa(
  id: id,
  nombre: nombre,
  propia: propia,
  color: color,
  geometria: GeometriaZona.desdeGeojson({
    'type': 'Polygon',
    'coordinates': [
      [
        [-56.2, -34.9],
        [-56.1, -34.9],
        [-56.1, -34.8],
        [-56.2, -34.8],
        [-56.2, -34.9],
      ],
    ],
  })!,
);

void main() {
  group('el color del borde', () {
    test('el fondo liso es el del mapa', () {
      expect(ColoresZona.fondoLiso, ColoresMapa.fondo);
    });

    test('sin color o con uno roto, el azul primario', () {
      expect(ColoresZona.borde(null), ColoresZona.porDefecto);
      expect(ColoresZona.borde('azul'), ColoresZona.porDefecto);
      expect(ColoresZona.borde('#12345'), ColoresZona.porDefecto);
      expect(ColoresZona.borde('#GGGGGG'), ColoresZona.porDefecto);
    });

    test('un color que ya contrasta queda como lo eligió el coordinador', () {
      for (final hex in const ['#13407A', '#1F6E3A', '#5B6B82', '#7A4E9E', '#A8312A']) {
        final color = ColoresZona.borde(hex);

        expect(color, Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)), reason: hex);
        expect(ColoresZona.contraste(color), greaterThanOrEqualTo(3), reason: hex);
      }
    });

    test('todos los colores, claros incluidos, terminan con contraste de al menos 3:1', () {
      for (final hex in const [
        '#FFFF00',
        '#FFFFFF',
        '#FFD966',
        '#9FD5F0',
        '#E0B43C',
        '#A98330',
        '#00FF00',
        '#F6F5F0',
        '#DDE8D3',
        '#ffc0cb',
        '#000000',
      ]) {
        expect(
          ColoresZona.contraste(ColoresZona.borde(hex)),
          greaterThanOrEqualTo(ColoresZona.contrasteMinimo),
          reason: hex,
        );
      }
    });

    test('un color claro se oscurece sin cambiar de tono', () {
      final amarillo = ColoresZona.borde('#FFD966');

      expect(amarillo, isNot(const Color(0xFFFFD966)));
      // Sigue siendo un amarillo: el rojo domina sobre el azul.
      expect((amarillo.r * 255), greaterThan(amarillo.b * 255));
    });
  });

  group('ZonaMapa.desde', () {
    test('la propia lleva «Tu zona · nombre»; las demás, el nombre', () {
      final propia = ZonaMapa.desde(_zona('a', 'Cerro Norte', propia: true));
      final otra = ZonaMapa.desde(_zona('b', 'La Teja'));

      expect(propia.rotulo, 'Tu zona · Cerro Norte');
      expect(propia.propia, isTrue);
      expect(otra.rotulo, 'La Teja');
      expect(otra.propia, isFalse);
    });

    test('trae el punto del nombre y el borde ya con contraste', () {
      final zona = ZonaMapa.desde(_zona('a', 'Centro', color: '#FFFF00'));

      expect(zona.puntoRotulo, isNotNull);
      expect(zona.poligonos, hasLength(1));
      expect(ColoresZona.contraste(zona.color), greaterThanOrEqualTo(3));
    });
  });

  group('lo que se le dice al lector de pantalla', () {
    test('sin zonas no se dice nada', () {
      expect(TextosMapaZonas.paraElLector(const []), isNull);
    });

    test(
      'nombra solo la propia: las de otros colportores no se mencionan ni se cuentan (#654)',
      () {
        expect(
          TextosMapaZonas.paraElLector([
            _zona('a', 'Cerro Norte', propia: true),
            _zona('b', 'La Teja'),
          ]),
          'Tu zona: Cerro Norte.',
        );
        expect(
          TextosMapaZonas.paraElLector([
            _zona('a', 'Cerro Norte', propia: true),
            _zona('b', 'La Teja'),
            _zona('c', 'Belvedere'),
          ]),
          'Tu zona: Cerro Norte.',
        );
      },
    );

    test('solo las demás: no se dice nada ni se inventa una zona propia (#654)', () {
      expect(
        TextosMapaZonas.paraElLector([_zona('b', 'La Teja'), _zona('c', 'Belvedere')]),
        isNull,
      );
    });

    test('dos zonas propias (dos campañas) se unen con «y»; con tres, comas', () {
      expect(
        TextosMapaZonas.paraElLector([
          _zona('a', 'Centro', propia: true),
          _zona('b', 'Cordón', propia: true),
        ]),
        'Tu zona: Centro y Cordón.',
      );
      expect(
        TextosMapaZonas.paraElLector([
          _zona('a', 'Centro', propia: true),
          _zona('b', 'Cordón', propia: true),
          _zona('c', 'Pocitos', propia: true),
        ]),
        'Tu zona: Centro, Cordón y Pocitos.',
      );
    });
  });
}
