// Test de data: el SHA-256 de un archivo real, contra valores conocidos.
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/calculador_checksum_sha256.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporal;
  const calculador = CalculadorChecksumSha256();

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('checksum_test_');
  });

  tearDown(() => temporal.delete(recursive: true));

  Future<String> ruta(List<int> bytes) async {
    final archivo = File(p.join(temporal.path, 'a.pmtiles'));
    await archivo.writeAsBytes(bytes);
    return archivo.path;
  }

  test('«abc» da el SHA-256 de referencia, en hex minúscula', () async {
    final resultado = await calculador.calcular(await ruta(utf8.encode('abc')));

    expect(resultado, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('un archivo vacío da el SHA-256 de la nada', () async {
    final resultado = await calculador.calcular(await ruta(const []));

    expect(resultado, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('un archivo de varios bloques (más de 64 KB) da el mismo que sha256sum', () async {
    // Un millón de «a»: el vector de prueba de la norma FIPS 180-4.
    final resultado = await calculador.calcular(await ruta(List.filled(1000000, 0x61)));

    expect(resultado, 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
  });

  test('un solo byte distinto cambia el resultado', () async {
    final bytes = List.filled(200000, 7);
    final antes = await calculador.calcular(await ruta(bytes));

    bytes[150000] = 8;
    final despues = await calculador.calcular(await ruta(bytes));

    expect(despues, isNot(antes));
  });

  test('un archivo que no existe lanza, no devuelve el hash de la nada', () async {
    await expectLater(
      calculador.calcular(p.join(temporal.path, 'no-esta.pmtiles')),
      throwsA(isA<FileSystemException>()),
    );
  });
}
