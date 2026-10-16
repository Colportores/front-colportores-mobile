// Test de data: el catálogo `catalogo.json` del bucket `mapas` como paquetes (HU-SYNC-010, #189).
// El de ejemplo (test/fixtures/tiles/catalogo_ejemplo.json) sigue el formato v1 de backend: no es
// el que se publica.
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/models/catalogo_tiles_model.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:test/test.dart';

void main() {
  final base = Uri.parse('https://x.supabase.co/storage/v1/object/public/mapas/catalogo.json');
  late Map<String, dynamic> ejemplo;
  late List<Map<String, dynamic>> descartados;

  setUp(() {
    ejemplo =
        jsonDecode(File('test/fixtures/tiles/catalogo_ejemplo.json').readAsStringSync())
            as Map<String, dynamic>;
    descartados = [];
  });

  List<PaqueteTiles> leer(Object? catalogo) {
    return CatalogoTilesModel.desdeJson(
      catalogo is String ? catalogo : jsonEncode(catalogo),
      base,
      descartado: (id, motivo) => descartados.add({'id': id, 'motivo': motivo}),
    );
  }

  Map<String, dynamic> paquete([int i = 0]) =>
      Map<String, dynamic>.from((ejemplo['paquetes'] as List<dynamic>)[i] as Map<String, dynamic>);

  Map<String, dynamic> con(Map<String, dynamic> paquete) => {
    ...ejemplo,
    'paquetes': [paquete],
  };

  Map<String, dynamic> parte0(Map<String, dynamic> paquete) =>
      Map<String, dynamic>.from((paquete['partes'] as List<dynamic>).first as Map<String, dynamic>);

  group('el catálogo de ejemplo', () {
    test('trae los tres paquetes, con el nivel y el ámbito de cada uno', () {
      final paquetes = leer(ejemplo);

      expect(paquetes.map((p) => p.id), ['ciudad-montevideo', 'ciudad-salto', 'zona-centro-mvd']);
      expect(paquetes.map((p) => p.nivel), [
        NivelCobertura.ciudad,
        NivelCobertura.ciudad,
        NivelCobertura.zona,
      ]);
      expect(paquetes[0].ambitoId, '0b9e0f10-0000-4000-8000-000000000001');
      expect(paquetes[0].nombre, 'Montevideo');
      expect(paquetes[2].nombre, isNull);
      expect(descartados, isEmpty);
    });

    test('Montevideo es un solo archivo de 10 920 234 bytes (11 MB), con la versión del archivo', () {
      final montevideo = leer(ejemplo).first;

      expect(montevideo.partes, hasLength(1));
      expect(montevideo.tamanoBytes, 10920234);
      expect(montevideo.megabytes, 11);
      expect(montevideo.version, montevideo.partes.first.sha256);
      expect(
        montevideo.partes.first.origen,
        Uri.parse(
          'https://x.supabase.co/storage/v1/object/public/mapas/ciudad-montevideo-3f9c1a2b7d44.pmtiles',
        ),
      );
    });

    test('una ciudad en dos archivos trae las dos partes, en orden, y el tamaño es la suma', () {
      final salto = leer(ejemplo)[1];

      expect(salto.partes, hasLength(2));
      expect(salto.partes.map((p) => p.tamanoBytes), [41500000, 38250000]);
      expect(salto.tamanoBytes, 79750000);
      expect(salto.megabytes, 80);
      expect(salto.partes[0].origen.pathSegments.last, 'ciudad-salto-9a1b2c3d4e5f-p1.pmtiles');
      expect(salto.partes[1].origen.pathSegments.last, 'ciudad-salto-0f1e2d3c4b5a-p2.pmtiles');
      expect(salto.partes[0].huella, salto.partes[0].sha256.substring(0, 12));
    });

    test('las rutas de las partes se resuelven contra la URL del catálogo', () {
      final otra = Uri.parse(
        'https://otro.supabase.co/storage/v1/object/public/mapas/catalogo.json',
      );

      final paquetes = CatalogoTilesModel.desdeJson(jsonEncode(ejemplo), otra);

      expect(paquetes.first.partes.first.origen.host, 'otro.supabase.co');
    });

    test('lo que la app no usa (retirados, estilo, bbox) se ignora', () {
      expect(ejemplo.containsKey('retirados'), isTrue);

      expect(leer(ejemplo), hasLength(3));
    });
  });

  group('un catálogo que no sirve', () {
    test('que no es JSON, lanza FormatException', () {
      expect(() => leer('<html>502</html>'), throwsFormatException);
    });

    test('que no es un objeto, lanza FormatException', () {
      expect(() => leer('[]'), throwsFormatException);
    });

    test('de otra versión del formato, lanza FormatException', () {
      expect(() => leer({...ejemplo, 'version': 2}), throwsFormatException);
      expect(() => leer({...ejemplo}..remove('version')), throwsFormatException);
    });

    test('sin la lista de paquetes, lanza FormatException', () {
      expect(() => leer({...ejemplo}..remove('paquetes')), throwsFormatException);
      expect(() => leer({...ejemplo, 'paquetes': 'x'}), throwsFormatException);
    });

    test('con la lista vacía, no hay paquetes y no es un error', () {
      expect(leer({...ejemplo, 'paquetes': <Object?>[]}), isEmpty);
    });
  });

  group('un paquete que no cumple el contrato se descarta solo, sin tirar el resto', () {
    void expectDescartado(Map<String, dynamic> roto, String motivo) {
      final paquetes = leer({
        ...ejemplo,
        'paquetes': [roto, paquete(1)],
      });

      expect(paquetes.map((p) => p.id), ['ciudad-salto']);
      expect(descartados, hasLength(1));
      expect(descartados.single['motivo'], contains(motivo));
    }

    test('con un id que no sirve de nombre de archivo', () {
      for (final id in ['', '../x', 'a/b', 'con espacio', 'a' * 81, 'ñandú']) {
        descartados.clear();
        expectDescartado({...paquete(), 'id': id}, 'id');
      }
    });

    test('con un id que no es texto', () {
      expectDescartado({...paquete(), 'id': 5}, 'id');
    });

    test('con un nivel desconocido', () {
      expectDescartado({...paquete(), 'nivel': 'planeta'}, 'nivel');
    });

    test('de zona o ciudad sin ambito_id', () {
      expectDescartado({...paquete()}..remove('ambito_id'), 'ambito_id');
      descartados.clear();
      expectDescartado({...paquete(), 'ambito_id': '  '}, 'ambito_id');
    });

    test('sin version', () {
      expectDescartado({...paquete()}..remove('version'), 'version');
      descartados.clear();
      expectDescartado({...paquete(), 'version': ' '}, 'version');
    });

    test('sin partes', () {
      expectDescartado({...paquete()}..remove('partes'), 'partes');
      descartados.clear();
      expectDescartado({...paquete(), 'partes': <Object?>[]}, 'partes');
    });

    test('con una parte que no es un objeto', () {
      expectDescartado({
        ...paquete(),
        'partes': ['x'],
      }, 'archivo');
    });

    test('con una parte de tamaño inválido', () {
      for (final tamano in [0, -5, 'grande', 1.5, null]) {
        descartados.clear();
        final roto = paquete();
        roto['partes'] = [
          {...parte0(roto), 'tamano_bytes': tamano},
        ];
        expectDescartado(roto, 'tamaño');
      }
    });

    test('con un checksum que no es un SHA-256', () {
      for (final sha in ['abc', 'z' * 64, 'a' * 63, 'a' * 65, null, 5]) {
        descartados.clear();
        final roto = paquete();
        roto['partes'] = [
          {...parte0(roto), 'sha256': sha},
        ];
        expectDescartado(roto, 'sha256');
      }
    });

    test('con una ruta de parte que se sale del bucket', () {
      for (final ruta in [
        '../otro/archivo.pmtiles',
        '/storage/otro.pmtiles',
        '//otro.host/x.pmtiles',
        'https://otro.host/x.pmtiles',
        'file:///data/x.pmtiles',
        'a/./b.pmtiles',
        'x.pmtiles?token=1',
        'x.pmtiles#frag',
        '',
        'a/../../b.pmtiles',
      ]) {
        descartados.clear();
        final roto = paquete();
        roto['partes'] = [
          {...parte0(roto), 'archivo': ruta},
        ];
        expectDescartado(roto, 'ruta');
      }
    });

    test('con una parte sin archivo', () {
      final roto = paquete();
      roto['partes'] = [
        {...parte0(roto)}..remove('archivo'),
      ];

      expectDescartado(roto, 'archivo');
    });

    test('con un id que ya apareció, se queda el primero', () {
      final paquetes = leer({
        ...ejemplo,
        'paquetes': [paquete(), paquete(), paquete(1)],
      });

      expect(paquetes.map((p) => p.id), ['ciudad-montevideo', 'ciudad-salto']);
      expect(descartados.single['motivo'], contains('repetido'));
    });

    test('que no es un objeto', () {
      final paquetes = leer({
        ...ejemplo,
        'paquetes': ['x', 5, null, paquete()],
      });

      expect(paquetes.map((p) => p.id), ['ciudad-montevideo']);
      expect(descartados, hasLength(3));
      expect(descartados.every((d) => d['id'] == null), isTrue);
    });
  });

  group('lo que se normaliza', () {
    test('el SHA-256 en mayúsculas pasa a minúsculas', () {
      final p = paquete();
      p['partes'] = [
        {...parte0(p), 'sha256': (parte0(p)['sha256'] as String).toUpperCase()},
      ];

      expect(leer(con(p)).single.partes.single.sha256, parte0(paquete())['sha256']);
    });

    test('Uruguay no necesita ámbito, y si lo trae se ignora', () {
      final uruguay = {...paquete(), 'id': 'uruguay', 'nivel': 'uruguay', 'ambito_id': 'x'};

      final paquetes = leer(con(uruguay));

      expect(paquetes.single.nivel, NivelCobertura.uruguay);
      expect(paquetes.single.ambitoId, isNull);
      expect(leer(con({...uruguay}..remove('ambito_id'))), hasLength(1));
    });

    test('el nombre se recorta y uno vacío queda sin nombre', () {
      expect(leer(con({...paquete(), 'nombre': '  Montevideo '})).single.nombre, 'Montevideo');
      expect(leer(con({...paquete(), 'nombre': ' '})).single.nombre, isNull);
      expect(leer(con({...paquete(), 'nombre': 5})).single.nombre, isNull);
    });

    test('el ámbito se recorta', () {
      expect(leer(con({...paquete(), 'ambito_id': ' abc '})).single.ambitoId, 'abc');
    });
  });
}
