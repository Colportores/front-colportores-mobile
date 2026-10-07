// Test de data: el catálogo de mapas leído por HTTP, con un cliente simulado.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/datasources/catalogo_paquetes_tiles_http.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final url = CatalogoPaquetesTilesHttp.urlDeSupabase('https://x.supabase.co');
  late String ejemplo;

  setUpAll(() {
    ejemplo = File('test/fixtures/tiles/catalogo_ejemplo.json').readAsStringSync();
  });

  CatalogoPaquetesTilesHttp crear(
    Future<http.StreamedResponse> Function(http.BaseRequest) responder, {
    Duration tiempoMaximo = const Duration(seconds: 5),
  }) {
    return CatalogoPaquetesTilesHttp(
      cliente: MockClient.streaming((pedido, _) => responder(pedido)),
      url: url,
      tiempoMaximo: tiempoMaximo,
      logger: loggerMudo(),
    );
  }

  http.StreamedResponse respuesta(String cuerpo, [int status = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(cuerpo)), status);

  test('la URL sale del bucket público «mapas» del proyecto, con o sin barra final', () {
    const esperada = 'https://x.supabase.co/storage/v1/object/public/mapas/catalogo.json';

    expect(CatalogoPaquetesTilesHttp.urlDeSupabase('https://x.supabase.co').toString(), esperada);
    expect(CatalogoPaquetesTilesHttp.urlDeSupabase('https://x.supabase.co/').toString(), esperada);
  });

  test('pide el catálogo con un GET, sin login y sin compresión', () async {
    late http.BaseRequest enviado;

    await crear((pedido) async {
      enviado = pedido;
      return respuesta(ejemplo);
    }).listar();

    expect(enviado.method, 'GET');
    expect(enviado.url, url);
    expect(enviado.headers['accept-encoding'], 'identity');
    expect(enviado.headers.containsKey('authorization'), isFalse);
    expect(enviado.headers.containsKey('apikey'), isFalse);
  });

  test('devuelve los paquetes, con las partes resueltas contra la URL del catálogo', () async {
    final paquetes = await crear((_) async => respuesta(ejemplo)).listar();

    expect(paquetes.map((p) => p.id), ['ciudad-montevideo', 'ciudad-salto', 'zona-centro-mvd']);
    expect(
      paquetes.first.partes.single.origen.toString(),
      'https://x.supabase.co/storage/v1/object/public/mapas/ciudad-montevideo-3f9c1a2b7d44.pmtiles',
    );
  });

  test('un cuerpo que llega en varios pedazos se arma completo', () async {
    final bytes = utf8.encode(ejemplo);
    final mitad = bytes.length ~/ 2;

    final paquetes = await crear(
      (_) async => http.StreamedResponse(
        Stream.fromIterable([bytes.sublist(0, mitad), bytes.sublist(mitad)]),
        200,
      ),
    ).listar();

    expect(paquetes, hasLength(3));
  });

  group('lo que sale mal', () {
    test('un código que no es 200 es un ErrorServidorTiles con ese código', () async {
      for (final status in [404, 500, 503]) {
        await expectLater(
          crear((_) async => respuesta('', status)).listar(),
          throwsA(isA<ErrorServidorTiles>().having((e) => e.status, 'status', status)),
        );
      }
    });

    test('un 206 tampoco es el catálogo', () async {
      await expectLater(
        crear((_) async => respuesta(ejemplo, 206)).listar(),
        throwsA(isA<ErrorServidorTiles>()),
      );
    });

    test('sin red (SocketException, ClientException) es un ErrorRedTiles', () async {
      for (final error in <Object>[
        const SocketException('sin ruta'),
        http.ClientException('cortado'),
        const HandshakeException('tls'),
      ]) {
        await expectLater(
          crear((_) async => throw error).listar(),
          throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', error)),
        );
      }
    });

    test('un servidor que no contesta es un ErrorRedTiles por el tiempo agotado', () async {
      final nunca = Completer<http.StreamedResponse>();

      await expectLater(
        crear((_) => nunca.future, tiempoMaximo: const Duration(milliseconds: 20)).listar(),
        throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', isA<TimeoutException>())),
      );
    });

    test('un cuerpo que se corta a mitad es un ErrorRedTiles', () async {
      Stream<List<int>> cortado() async* {
        yield utf8.encode('{"version"');
        throw const SocketException('cortado');
      }

      await expectLater(
        crear((_) async => http.StreamedResponse(cortado(), 200)).listar(),
        throwsA(isA<ErrorRedTiles>()),
      );
    });

    test('un cuerpo que se queda callado es un ErrorRedTiles por el tiempo agotado', () async {
      final cuerpo = StreamController<List<int>>()..add(utf8.encode('{"version"'));

      await expectLater(
        crear(
          (_) async => http.StreamedResponse(cuerpo.stream, 200),
          tiempoMaximo: const Duration(milliseconds: 20),
        ).listar(),
        throwsA(isA<ErrorRedTiles>()),
      );
      await cuerpo.close();
    });

    test('algo que no es JSON (la página de un portal cautivo) es una FormatException', () async {
      await expectLater(
        crear((_) async => respuesta('<html>Iniciá sesión en el wifi</html>')).listar(),
        throwsFormatException,
      );
    });

    test('un cuerpo de más de 1 MB no es el catálogo', () async {
      final enorme = '{"version":1,"paquetes":[],"relleno":"${'a' * (1024 * 1024)}"}';

      await expectLater(crear((_) async => respuesta(enorme)).listar(), throwsFormatException);
    });

    test('un error de programación no se disfraza de falla de red', () async {
      await expectLater(crear((_) async => throw StateError('bug')).listar(), throwsStateError);
    });

    test('un paquete que no cumple el contrato se descarta y los demás se devuelven', () async {
      final catalogo = jsonDecode(ejemplo) as Map<String, dynamic>;
      (catalogo['paquetes'] as List<dynamic>).insert(0, {'id': 'roto'});

      final paquetes = await crear((_) async => respuesta(jsonEncode(catalogo))).listar();

      expect(paquetes.map((p) => p.id), ['ciudad-montevideo', 'ciudad-salto', 'zona-centro-mvd']);
    });
  });
}
