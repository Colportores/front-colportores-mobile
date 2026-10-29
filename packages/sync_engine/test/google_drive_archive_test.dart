// `GoogleDriveArchive` contra un Drive de mentira que habla la API v3: lo que se
// verifica es el contrato con Drive (carpeta oculta, subida de una sola
// petición, metadatos de la cadena, errores que la app distingue), no a Drive.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Un Drive en memoria con la forma de la API v3.
class _DriveFalso {
  final archivos = <String, Map<String, Object?>>{};
  final bytes = <String, List<int>>{};
  final pedidos = <http.Request>[];
  String? token = 'token-1';

  /// Si se pone, la próxima respuesta es esta.
  ({int status, String cuerpo})? falla;

  var _n = 0;
  var _t = DateTime.utc(2026, 11, 2, 22);

  http.Client get cliente => MockClient((req) async {
        pedidos.add(req);
        if (falla case final f?) {
          falla = null;
          return http.Response(f.cuerpo, f.status);
        }
        if (req.headers['Authorization'] != 'Bearer $token') {
          return http.Response('{}', 401);
        }
        final ruta = req.url.path;
        if (req.method == 'GET' && ruta == '/drive/v3/files') return _listar(req);
        if (req.method == 'POST' && ruta == '/upload/drive/v3/files') return _subir(req);
        final id = ruta.split('/').last;
        if (req.method == 'GET') {
          return bytes.containsKey(id)
              ? http.Response.bytes(bytes[id]!, 200)
              : http.Response('{}', 404);
        }
        if (req.method == 'DELETE') {
          if (archivos.remove(id) == null) return http.Response('{}', 404);
          bytes.remove(id);
          return http.Response('', 204);
        }
        return http.Response('{}', 400);
      });

  http.Response _listar(http.Request req) {
    expect(req.url.queryParameters['spaces'], 'appDataFolder');
    final todos = archivos.values.toList();
    final pagina = req.url.queryParameters['pageToken'];
    // Páginas de 2 para probar la paginación.
    final desde = pagina == null ? 0 : int.parse(pagina);
    final trozo = todos.skip(desde).take(2).toList();
    return http.Response(
      jsonEncode({
        'files': trozo,
        if (desde + 2 < todos.length) 'nextPageToken': '${desde + 2}',
      }),
      200,
    );
  }

  http.Response _subir(http.Request req) {
    expect(req.url.queryParameters['uploadType'], 'multipart');
    expect(req.headers['Content-Type'], startsWith('multipart/related; boundary='));
    final limite = req.headers['Content-Type']!.split('boundary=').last;
    final cuerpo = req.bodyBytes;
    final texto = latin1.decode(cuerpo);
    final partes = texto.split('--$limite');
    // partes[1] = metadatos, partes[2] = bytes.
    final jsonTexto = partes[1].split('\r\n\r\n')[1].trim();
    final meta = jsonDecode(utf8.decode(latin1.encode(jsonTexto))) as Map<String, Object?>;
    final inicio = texto.indexOf('application/octet-stream\r\n\r\n') +
        'application/octet-stream\r\n\r\n'.length;
    final fin = texto.lastIndexOf('\r\n--$limite--');
    final contenido = cuerpo.sublist(inicio, fin);

    expect(meta['parents'], ['appDataFolder']);
    final id = 'f${++_n}';
    _t = _t.add(const Duration(seconds: 1));
    archivos[id] = {
      'id': id,
      'createdTime': _t.toIso8601String(),
      'size': '${contenido.length}',
      'sha256Checksum': FakeCrypto.hashOf(contenido),
      'description': meta['description'],
      'appProperties': meta['appProperties'],
    };
    bytes[id] = contenido;
    return http.Response(jsonEncode(archivos[id]), 200);
  }
}

void main() {
  late _DriveFalso drive;
  late GoogleDriveArchive archivo;

  setUp(() {
    drive = _DriveFalso();
    archivo = GoogleDriveArchive(
      token: () async => drive.token,
      digest: FakeCrypto.hashOf,
      client: drive.cliente,
    );
  });

  test('un archivo nuevo está vacío', () async {
    expect(await archivo.list(), isEmpty);
  });

  test('sube a la carpeta oculta de la app, con la cadena en los metadatos', () async {
    final instante = DateTime.utc(2026, 11, 2, 21, 59, 58, 500);
    final base = await archivo.upload(
        payload: const [1, 2, 3], parentId: null, watermark: 'w-1', exportedAt: instante);
    final inc = await archivo.upload(
        payload: const [4, 5], parentId: base.id, watermark: 'w-2');

    expect(base.isBase, isTrue);
    expect(inc.parentId, base.id);
    expect(base.watermark, 'w-1');
    expect(base.exportedAt, instante);
    expect(inc.exportedAt, isNull);
    expect(base.contentHash, FakeCrypto.hashOf(const [1, 2, 3]));
    expect(base.bytes, 3);
    expect((await archivo.list()).map((e) => e.id), [base.id, inc.id]);
  });

  test('el identificador de llave viaja en appProperties y vuelve en list', () async {
    final e = await archivo.upload(
        payload: const [1], parentId: null, watermark: 'w', keyId: 'abc123');
    final sin = await archivo.upload(payload: const [2], parentId: e.id, watermark: 'w');

    expect(e.keyId, 'abc123');
    expect(drive.archivos[e.id]!['appProperties'], containsPair('key_id', 'abc123'));
    expect(sin.keyId, isNull);
    expect((await archivo.list()).map((x) => x.keyId), ['abc123', null]);
  });

  test('el hash que calculó Drive viene en la entrada y coincide con el subido', () async {
    final e = await archivo.upload(
        payload: const [9, 8, 7], parentId: null, watermark: 'w');

    expect(e.storedHash, e.contentHash);
    expect(e.corrupta, isFalse);
  });

  test('si Drive guardó otra cosa, la entrada sale corrupta', () async {
    final e = await archivo.upload(
        payload: const [9, 8, 7], parentId: null, watermark: 'w');
    drive.archivos[e.id]!['sha256Checksum'] = 'otro';

    final listada = (await archivo.list()).single;
    expect(listada.corrupta, isTrue);
    expect(buildChain([listada]).problems, {ChainProblem.corrupt});
  });

  test('lo que sube es lo que baja, byte por byte', () async {
    // Bytes que no son texto: un backup cifrado es indistinguible de ruido, y
    // cualquier reinterpretación como UTF-8 lo rompería. Incluye el separador
    // del multipart.
    final payload = [
      for (var i = 0; i < 256; i++) i,
      ...utf8.encode('\r\n--colportores-backup-multipart--'),
    ];

    final e = await archivo.upload(payload: payload, parentId: null, watermark: 'w');
    expect(await archivo.download(e.id), payload);
  });

  test('el watermark largo no choca con el límite de las propiedades', () async {
    final largo = 'x' * 500;
    final e = await archivo.upload(payload: const [1], parentId: null, watermark: largo);

    expect((await archivo.list()).single.watermark, largo);
    expect(e.watermark, largo);
  });

  test('un archivo sin los metadatos de la cadena no es un eslabón', () async {
    drive.archivos['suelto'] = {
      'id': 'suelto',
      'createdTime': DateTime.utc(2026, 11, 1).toIso8601String(),
      'appProperties': {'otra_cosa': 'x'},
    };

    expect(await archivo.list(), isEmpty);
  });

  test('pagina: no pierde entradas cuando son más de una página', () async {
    for (var i = 0; i < 5; i++) {
      await archivo.upload(payload: [i], parentId: null, watermark: 'w-$i');
    }

    expect(await archivo.list(), hasLength(5));
  });

  test('delete borra, y borrar lo que ya no está no es un error', () async {
    final e = await archivo.upload(payload: const [1], parentId: null, watermark: 'w');

    await archivo.delete(e.id);
    await archivo.delete(e.id);

    expect(await archivo.list(), isEmpty);
  });

  group('errores que la app distingue', () {
    test('sin token no se pide nada a Drive, y no se toma por una revocación', () async {
      drive.token = null;

      await expectLater(
          archivo.list(),
          throwsA(isA<ArchiveSinToken>()
              .having((e) => e, 'no es 401', isNot(isA<ArchiveUnauthorized>()))));
      expect(drive.pedidos, isEmpty);
      expect(await archivo.isAuthorized, isFalse);
    });

    test('401: el permiso se perdió', () async {
      drive.falla = (status: 401, cuerpo: '{"error":{"errors":[{"reason":"authError"}]}}');

      await expectLater(archivo.list(), throwsA(isA<ArchiveUnauthorized>()));
    });

    test('403 por falta de permiso es lo mismo que un 401', () async {
      drive.falla = (
        status: 403,
        cuerpo: '{"error":{"errors":[{"reason":"insufficientPermissions"}]}}'
      );

      await expectLater(archivo.list(), throwsA(isA<ArchiveUnauthorized>()));
    });

    test('403 storageQuotaExceeded: el Drive no tiene espacio', () async {
      drive.falla = (
        status: 403,
        cuerpo: '{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}'
      );

      await expectLater(
          archivo.upload(payload: const [1], parentId: null, watermark: 'w'),
          throwsA(isA<ArchiveNoSpace>()));
      expect(drive.archivos, isEmpty, reason: 'una subida que falla no deja nada');
    });

    test('un límite de pedidos y un error del servidor son transitorios', () async {
      drive.falla = (
        status: 403,
        cuerpo: '{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}'
      );
      await expectLater(
          archivo.list(),
          throwsA(isA<ArchiveFailure>()
              .having((e) => e, 'no es de permiso', isNot(isA<ArchiveUnauthorized>()))
              .having((e) => e, 'no es de espacio', isNot(isA<ArchiveNoSpace>()))));

      drive.falla = (status: 503, cuerpo: '');
      await expectLater(
          archivo.list(),
          throwsA(isA<ArchiveFailure>()
              .having((e) => e, 'no es de permiso', isNot(isA<ArchiveUnauthorized>()))));
    });

    test('el mensaje de la falla no lleva el cuerpo de Drive', () async {
      drive.falla = (status: 500, cuerpo: 'cuenta ana@example.com');

      await expectLater(
          archivo.list(),
          throwsA(isA<ArchiveFailure>()
              .having((e) => '$e', 'texto', isNot(contains('ana@example.com')))));
    });
  });

  test('con un BackupService: base, incremental, verificación y rotación sobre Drive',
      () async {
    final snap = FakeSnapshot();
    final service = BackupService(
      archive: archivo,
      crypto: FakeCrypto(),
      snapshot: snap,
      policy: const BackupPolicy(maxPatches: 2),
    );

    final base = await service.backupNow(watermark: 'w-1');
    final i1 = await service.backupNow(watermark: 'w-2');
    final i2 = await service.backupNow(watermark: 'w-3');
    expect([base.isBase, i1.parentId, i2.parentId], [true, base.id, i1.id]);

    final informe = await service.verifyIntegrity();
    expect(informe.ok, isTrue);
    expect(informe.entries, 3);
    expect(drive.pedidos.where((p) => p.url.queryParameters['alt'] == 'media'), isEmpty,
        reason: 'verificar con el checksum de Drive no baja ningún blob');

    final nueva = await service.backupNow(watermark: 'w-4');
    expect(nueva.isBase, isTrue);
    expect((await archivo.list()).map((e) => e.id), [nueva.id]);
  });
}
