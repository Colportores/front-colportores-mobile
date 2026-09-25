// Archivo común del envoltorio de la DEK (ADR-006), contra un directorio temporal real.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

EnvoltorioDek _envoltorio(int relleno) => EnvoltorioDek(
  version: 1,
  algoritmo: EnvoltorioDek.algoritmoActual,
  parametros: ParametrosArgon2id.adr006,
  sal: Uint8List.fromList(List<int>.filled(16, relleno)),
  nonce: Uint8List.fromList(List<int>.filled(24, relleno)),
  cifrado: Uint8List.fromList(List<int>.filled(48, relleno)),
);

void main() {
  late Directory dir;
  late ArchivoEnvoltorioDek archivo;
  File enDisco() => File(p.join(dir.path, ArchivoEnvoltorioDek.nombreArchivoPorDefecto));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('envoltorio_');
    archivo = ArchivoEnvoltorioDek(directorio: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('ArchivoEnvoltorioDek', () {
    test('dado un equipo sin envoltorio, no existe y leerlo da null', () async {
      expect(await archivo.existe(), isFalse);
      expect(await archivo.leer(), isNull);
    });

    test('dado un envoltorio escrito, cuando se lee, vuelve igual', () async {
      await archivo.escribir(_envoltorio(1));

      expect(await archivo.existe(), isTrue);
      expect(await archivo.leer(), _envoltorio(1));
    });

    test('cuando se escribe otro, reemplaza al anterior y no deja el temporal', () async {
      await archivo.escribir(_envoltorio(1));
      await archivo.escribir(_envoltorio(2));

      expect(await archivo.leer(), _envoltorio(2));
      expect(await File('${enDisco().path}.tmp').exists(), isFalse);
    });

    test('cuando se borra, no queda nada; y borrar sin archivo no falla', () async {
      await archivo.escribir(_envoltorio(1));
      await File('${enDisco().path}.tmp').writeAsString('restos de una escritura cortada');

      await archivo.borrar();

      expect(await archivo.existe(), isFalse);
      expect(await File('${enDisco().path}.tmp').exists(), isFalse);
      await expectLater(archivo.borrar(), completes);
    });

    test('dado un archivo que no es un envoltorio, cuando se lee, lanza '
        'EnvoltorioCorruptoException', () async {
      await enDisco().writeAsString('basura');

      await expectLater(archivo.leer(), throwsA(isA<EnvoltorioCorruptoException>()));
    });

    test('dado un directorio que no existe, cuando escribe, lanza ArchivoEnvoltorioException '
        'con la causa de disco', () async {
      final roto = ArchivoEnvoltorioDek(
        directorio: () async => Directory(p.join(dir.path, 'no', 'existe')),
      );

      await expectLater(
        roto.escribir(_envoltorio(1)),
        throwsA(
          isA<ArchivoEnvoltorioException>()
              .having((e) => e.operacion, 'operacion', 'escribir')
              .having((e) => e.causa, 'causa', isA<FileSystemException>()),
        ),
      );
    });

    test('la excepción no lleva la ruta', () {
      const falla = ArchivoEnvoltorioException(
        operacion: 'leer',
        causa: FileSystemException('x', '/data/user/0/app/dek_envuelta.json'),
      );

      expect(falla.toString(), 'ArchivoEnvoltorioException(leer)');
    });
  });
}
