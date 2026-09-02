// `DriveArchive` contra el archivo remoto de verdad.
//
// Corre la suite ejecutable de `port_contracts.dart`: lo mismo que el motor da
// por sentado del `FakeArchive` tiene que cumplirlo el adaptador, o el backup
// funciona en los tests y falla en el celular.
//
//   cd prototipo-sync && docker compose up -d drive-mock
//   DRIVE_URL=http://localhost:8090 dart test test/drive_archive_test.dart
//
// Se saltea sin `DRIVE_URL`, así que `dart test` sigue corriendo entero en la
// VM sin servicios (§5.9).

import 'dart:io';

import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/port_contracts.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['DRIVE_URL'];
  if (url == null) {
    // ignore: avoid_print
    print('DRIVE_URL sin definir: se saltea el archivo remoto');
    return;
  }

  DriveArchive crear() => DriveArchive(
        baseUrl: Uri.parse('$url/'),
        token: () async => 'token-de-prueba',
        // El mismo digest que el CryptoPort en juego. Si no coinciden,
        // verifyChain() da cadena rota siempre.
        digest: FakeCrypto.hashOf,
      );

  // El contrato exige un archivo **vacío**: contra un servicio de verdad eso
  // hay que hacerlo, no suponerlo.
  setUp(() async {
    final a = crear();
    for (final e in await a.list()) {
      await a.delete(e.id);
    }
  });

  runArchiveContract('DriveArchive', crear);

  test('un archivo sin metadatos de cadena no entra en la cadena', () async {
    final a = crear();
    // Un archivo suelto en el appDataFolder: subido por una versión vieja, o a
    // medio subir. Si se colara como eslabón, la cadena daría rota para
    // siempre y el colportor no podría restaurar nada.
    final req = await HttpClient().postUrl(Uri.parse('$url/files'));
    const limite = '----suelto';
    req.headers.set('Content-Type', 'multipart/form-data; boundary=$limite');
    req.write('--$limite\r\n'
        'Content-Disposition: form-data; name="file"; filename="suelto.bin"\r\n'
        '\r\n'
        'basura\r\n'
        '--$limite--\r\n');
    await (await req.close()).drain<void>();

    expect(await a.list(), isEmpty,
        reason: 'un archivo sin app_properties no es un eslabón');
  });

  test('lo que sube es lo que baja, byte por byte', () async {
    final a = crear();
    // Bytes que no son texto: un backup cifrado es indistinguible de ruido, y
    // cualquier reinterpretación como UTF-8 lo rompería.
    final payload = [for (var i = 0; i < 256; i++) i];

    final e = await a.upload(payload: payload, parentId: null, watermark: 'w');
    expect(await a.download(e.id), payload);
    expect(e.contentHash, FakeCrypto.hashOf(payload),
        reason: 'el hash lo calcula el cliente sobre lo que sube');
  });
}
