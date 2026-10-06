// Test de data: ArchivosTilesIo contra un directorio temporal real.
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/archivos_tiles_io.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporal;
  late Directory directorio;
  late ArchivosTilesIo archivos;

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('tiles_test_');
    directorio = Directory(p.join(temporal.path, 'tiles'));
    archivos = ArchivosTilesIo(directorio);
  });

  tearDown(() => temporal.delete(recursive: true));

  test('dada una clave, el .part y el .pmtiles quedan en el directorio de la app', () {
    expect(
      archivos.rutaFinal('ciudad-mvd-p1-3f9c1a2b7d44'),
      p.join(directorio.path, 'ciudad-mvd-p1-3f9c1a2b7d44.pmtiles'),
    );
    expect(
      archivos.rutaParcial('ciudad-mvd-p1-3f9c1a2b7d44'),
      p.join(directorio.path, 'ciudad-mvd-p1-3f9c1a2b7d44.pmtiles.part'),
    );
  });

  test('dada una clave que se saldría del directorio, la rechaza', () {
    for (final clave in ['../otro', '', 'a/b', r'a\b', 'a.b', 'con espacio']) {
      expect(() => archivos.rutaFinal(clave), throwsArgumentError, reason: clave);
      expect(() => archivos.rutaParcial(clave), throwsArgumentError, reason: clave);
    }
  });

  test('dado un .part, anexa, trunca, renombra y borra', () async {
    final parcial = archivos.rutaParcial('zona-1');
    final destino = archivos.rutaFinal('zona-1');
    expect(await archivos.tamano(parcial), 0);
    expect(await archivos.existe(parcial), isFalse);

    final primera = await archivos.abrir(parcial, anexar: false);
    await primera.agregar([1, 2, 3]);
    await primera.cerrar();
    final segunda = await archivos.abrir(parcial, anexar: true);
    await segunda.agregar([4, 5]);
    await segunda.cerrar();
    expect(await File(parcial).readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await archivos.tamano(parcial), 5);

    final reescrita = await archivos.abrir(parcial, anexar: false);
    await reescrita.agregar([9]);
    await reescrita.cerrar();
    expect(await archivos.tamano(parcial), 1);

    await File(destino).writeAsBytes([7, 7]);
    await archivos.renombrar(parcial, destino);
    expect(await archivos.existe(parcial), isFalse);
    expect(await File(destino).readAsBytes(), [9]);

    await archivos.borrar(destino);
    await archivos.borrar(destino);
    expect(await archivos.existe(destino), isFalse);
  });

  test('abrir crea el directorio si todavía no existe', () async {
    expect(directorio.existsSync(), isFalse);

    final escritura = await archivos.abrir(archivos.rutaParcial('zona-1'), anexar: false);
    await escritura.cerrar();

    expect(directorio.existsSync(), isTrue);
  });

  group('listar', () {
    test('con el directorio sin crear, no hay archivos', () async {
      expect(await archivos.listar(), isEmpty);
    });

    test('devuelve los .pmtiles y los .part, con nombre, ruta, tamaño y fecha', () async {
      final final1 = archivos.rutaFinal('a-p1-aaaaaaaaaaaa');
      final parcial = archivos.rutaParcial('b-p1-bbbbbbbbbbbb');
      await directorio.create(recursive: true);
      await File(final1).writeAsBytes([1, 2, 3, 4]);
      await File(parcial).writeAsBytes([1, 2]);
      await File(p.join(directorio.path, 'registro.json')).writeAsString('{}');
      await File(p.join(directorio.path, 'registro.json.tmp')).writeAsString('{}');
      await Directory(p.join(directorio.path, 'otra.pmtiles')).create();

      final lista = await archivos.listar();

      expect(lista.map((a) => a.nombre).toSet(), {
        'a-p1-aaaaaaaaaaaa.pmtiles',
        'b-p1-bbbbbbbbbbbb.pmtiles.part',
      });
      final fin = lista.singleWhere((a) => a.esFinal);
      expect(fin.ruta, final1);
      expect(fin.bytes, 4);
      expect(fin.esParcial, isFalse);
      expect(fin.modificado.difference(DateTime.now()).abs(), lessThan(const Duration(minutes: 1)));
      final parte = lista.singleWhere((a) => a.esParcial);
      expect(parte.bytes, 2);
      expect(parte.esFinal, isFalse);
    });
  });

  test(
    'un disco lleno a mitad de la escritura sale como ErrorEspacioTiles',
    () async {
      // `/dev/full` acepta abrirse y falla con ENOSPC al escribir.
      final escritura = await archivos.abrir('/dev/full', anexar: false);

      await expectLater(escritura.agregar(List.filled(4096, 1)), throwsA(isA<ErrorEspacioTiles>()));
    },
    skip: Platform.isLinux ? false : 'solo Linux tiene /dev/full',
  );
}
