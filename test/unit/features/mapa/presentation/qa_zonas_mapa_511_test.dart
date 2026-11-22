// QA de HU-UBI-003 (#511): el color de ColoresZona y lo que viaja al estilo con datos que el
// coordinador puede mandar mal (formatos de color, nombres con emoji), y privacidad del toString.
import 'dart:convert';

import 'package:colportores_mobile/features/mapa/domain/entities/zona_del_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/geometria_zona.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:flutter_test/flutter_test.dart';

ZonaDelMapa _zona({String nombre = 'Cerro', String? color = '#1F6E3A', bool propia = false}) =>
    ZonaDelMapa(
      id: 'z-1',
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
  group('QA #511: el color que manda el coordinador', () {
    test('formatos que no son #RRGGBB (corto, con alfa, con espacio, nombre, vacío) caen al azul '
        'primario y contrastan', () {
      for (final malo in [
        '#fff',
        '#1F6E3AFF',
        ' #1F6E3A',
        '1F6E3A',
        'rojo',
        '',
        '#GGGGGG',
        '#1F6E3A\n',
      ]) {
        final c = ColoresZona.borde(malo);
        expect(c, ColoresZona.borde(null), reason: '«$malo»');
        expect(ColoresZona.contraste(c), greaterThanOrEqualTo(ColoresZona.contrasteMinimo));
      }
    });

    test('minúsculas valen igual que mayúsculas', () {
      expect(ColoresZona.borde('#1f6e3a'), ColoresZona.borde('#1F6E3A'));
    });

    test('blanco y negro: el blanco se oscurece hasta contrastar, el negro queda', () {
      expect(
        ColoresZona.contraste(ColoresZona.borde('#FFFFFF')),
        greaterThanOrEqualTo(ColoresZona.contrasteMinimo),
      );
      expect(ColoresZona.borde('#000000').toARGB32(), 0xFF000000);
    });
  });

  group('QA #511: lo que viaja al estilo', () {
    test('las colecciones con nombres raros se codifican a JSON (lo que cruza al lado nativo)', () {
      final zonas = [
        ZonaMapa.desde(_zona(nombre: 'Ñandú 🌳 "x" \\ \n', propia: true, color: null)),
        ZonaMapa.desde(_zona(nombre: 'Otra')),
      ];
      expect(
        () => jsonEncode(ConstructorEstiloMapa.coleccionRotulosDeZonas(zonas)),
        returnsNormally,
      );
      expect(() => jsonEncode(ConstructorEstiloMapa.coleccionZonas(zonas)), returnsNormally);
    });

    test('el color de cada feature es #rrggbb de 6 dígitos hex (lo que MapLibre acepta)', () {
      final zonas = [ZonaMapa.desde(_zona(color: '#FFEE00')), ZonaMapa.desde(_zona(color: null))];
      final formato = RegExp(r'^#[0-9a-fA-F]{6}$');
      for (final f in ConstructorEstiloMapa.coleccionZonas(zonas)['features'] as List) {
        expect(((f as Map)['properties'] as Map)['color'], matches(formato));
      }
    });
  });

  group('QA #511: privacidad', () {
    test('toString de la zona dibujada no vuelca nombre ni polígono', () {
      final z = ZonaMapa.desde(_zona(nombre: 'Barrio de Lucía', propia: true));
      expect(z.toString(), isNot(contains('Lucía')));
      expect(z.toString(), isNot(contains('-56.2')));
    });
  });
}
