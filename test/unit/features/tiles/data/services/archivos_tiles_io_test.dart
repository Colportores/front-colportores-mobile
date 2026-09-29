// Test de data: ArchivosTilesIo contra un directorio temporal real.
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/archivos_tiles_io.dart';
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

  test('dado un id, el .part y el .pmtiles quedan en el directorio de la app', () {
    expect(archivos.rutaFinal('zona-1'), p.join(directorio.path, 'zona-1.pmtiles'));
    expect(archivos.rutaParcial('zona-1'), p.join(directorio.path, 'zona-1.pmtiles.part'));
  });

  test('dado un id que se saldría del directorio, lo rechaza', () {
    expect(() => archivos.rutaFinal('../otro'), throwsArgumentError);
    expect(() => archivos.rutaParcial(''), throwsArgumentError);
  });

  test('dado un .part, anexa, trunca, renombra y borra', () async {
    final parcial = archivos.rutaParcial('zona-1');
    final destino = archivos.rutaFinal('zona-1');
    expect(await archivos.tamano(parcial), 0);

    final primera = await archivos.abrir(parcial, anexar: false);
    primera.agregar([1, 2, 3]);
    await primera.cerrar();
    final segunda = await archivos.abrir(parcial, anexar: true);
    segunda.agregar([4, 5]);
    await segunda.cerrar();
    expect(await File(parcial).readAsBytes(), [1, 2, 3, 4, 5]);

    final reescrita = await archivos.abrir(parcial, anexar: false);
    reescrita.agregar([9]);
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
}
