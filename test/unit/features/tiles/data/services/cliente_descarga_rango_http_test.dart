// Test de data: el cliente que baja un archivo desde un byte (Range), con un cliente HTTP simulado.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/cliente_descarga_rango_http.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final origen = Uri.parse('https://x.supabase.co/storage/v1/object/public/mapas/a.pmtiles');
  late http.BaseRequest enviado;

  ClienteDescargaRangoHttp crear(
    Future<http.StreamedResponse> Function(http.BaseRequest) responder, {
    Duration esperaRespuesta = const Duration(seconds: 5),
    Duration esperaPedazo = const Duration(seconds: 5),
  }) {
    return ClienteDescargaRangoHttp(
      cliente: MockClient.streaming((pedido, _) {
        enviado = pedido;
        return responder(pedido);
      }),
      esperaRespuesta: esperaRespuesta,
      esperaPedazo: esperaPedazo,
    );
  }

  http.StreamedResponse respuesta(int status, List<List<int>> pedazos, [Map<String, String>? h]) {
    return http.StreamedResponse(Stream.fromIterable(pedazos), status, headers: h ?? const {});
  }

  Future<List<int>> leer(RespuestaDescarga r) async => [
    for (final pedazo in await r.bytes.toList()) ...pedazo,
  ];

  group('el pedido', () {
    test('desde 0 es un GET del archivo entero, sin Range y sin compresión', () async {
      await crear(
        (_) async => respuesta(200, [
          [1],
        ]),
      ).pedir(origen, desde: 0);

      expect(enviado.method, 'GET');
      expect(enviado.url, origen);
      expect(enviado.headers.containsKey('range'), isFalse);
      expect(enviado.headers['accept-encoding'], 'identity');
    });

    test('desde un byte pide Range: bytes=<desde>-', () async {
      await crear(
        (_) async => respuesta(
          206,
          [
            [1],
          ],
          {'content-range': 'bytes 5000-9999/10000'},
        ),
      ).pedir(origen, desde: 5000);

      expect(enviado.headers['range'], 'bytes=5000-');
    });
  });

  group('la respuesta', () {
    test('un 200 manda el archivo entero, desde el byte 0, aunque se haya pedido otro', () async {
      final r = await crear(
        (_) async => respuesta(200, [
          [1, 2],
          [3],
        ]),
      ).pedir(origen, desde: 100);

      expect(r.desde, 0);
      expect(await leer(r), [1, 2, 3]);
    });

    test('un 206 dice desde qué byte viene el cuerpo, según Content-Range', () async {
      final r = await crear(
        (_) async => respuesta(
          206,
          [
            [4, 5],
          ],
          {'content-range': 'bytes 3-4/5'},
        ),
      ).pedir(origen, desde: 3);

      expect(r.desde, 3);
      expect(await leer(r), [4, 5]);
    });

    test('Content-Range con total desconocido también sirve', () async {
      final r = await crear(
        (_) async => respuesta(
          206,
          [
            [1],
          ],
          {'content-range': 'bytes 7-7/*'},
        ),
      ).pedir(origen, desde: 7);

      expect(r.desde, 7);
    });

    test('un 206 sin Content-Range, o con uno ilegible, es un error del servidor', () async {
      for (final encabezados in <Map<String, String>>[
        {},
        {'content-range': 'bytes */10000'},
        {'content-range': 'items 3-4/5'},
        {'content-range': 'bytes x-4/5'},
      ]) {
        await expectLater(
          crear(
            (_) async => respuesta(206, [
              [1],
            ], encabezados),
          ).pedir(origen, desde: 3),
          throwsA(isA<ErrorServidorTiles>().having((e) => e.status, 'status', 206)),
          reason: '$encabezados',
        );
      }
    });

    test('cualquier otro código es un ErrorServidorTiles, incluido el 416 y el 404', () async {
      for (final status in [301, 403, 404, 416, 500, 503]) {
        await expectLater(
          crear(
            (_) async => respuesta(status, [
              [1],
            ]),
          ).pedir(origen, desde: 10),
          throwsA(isA<ErrorServidorTiles>().having((e) => e.status, 'status', status)),
        );
      }
    });
  });

  group('la red', () {
    test('sin conexión antes de la respuesta es un ErrorRedTiles', () async {
      for (final error in <Object>[
        const SocketException('sin ruta'),
        http.ClientException('cortado'),
        const HandshakeException('tls'),
      ]) {
        await expectLater(
          crear((_) async => throw error).pedir(origen, desde: 0),
          throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', error)),
        );
      }
    });

    test('un servidor que no responde es un ErrorRedTiles por el tiempo agotado', () async {
      final nunca = Completer<http.StreamedResponse>();

      await expectLater(
        crear(
          (_) => nunca.future,
          esperaRespuesta: const Duration(milliseconds: 20),
        ).pedir(origen, desde: 0),
        throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', isA<TimeoutException>())),
      );
    });

    test('un error de programación no se disfraza de falla de red', () async {
      await expectLater(
        crear((_) async => throw StateError('bug')).pedir(origen, desde: 0),
        throwsStateError,
      );
    });

    test('un corte a mitad del cuerpo llega como error del flujo, con lo bajado antes', () async {
      Stream<List<int>> cortado() async* {
        yield [1, 2, 3];
        throw const SocketException('cortado');
      }

      final r = await crear(
        (_) async => http.StreamedResponse(cortado(), 200),
      ).pedir(origen, desde: 0);
      final recibido = <int>[];

      await expectLater(r.bytes.forEach(recibido.addAll), throwsA(isA<SocketException>()));
      expect(recibido, [1, 2, 3]);
    });

    test('un servidor que se calla a mitad del cuerpo termina con ErrorRedTiles', () async {
      final cuerpo = StreamController<List<int>>()..add([1, 2]);
      final r = await crear(
        (_) async => http.StreamedResponse(cuerpo.stream, 200),
        esperaPedazo: const Duration(milliseconds: 20),
      ).pedir(origen, desde: 0);
      final recibido = <int>[];

      await expectLater(
        r.bytes.forEach(recibido.addAll),
        throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', isA<TimeoutException>())),
      );
      expect(recibido, [1, 2]);
      await cuerpo.close();
    });

    test('un cuerpo que llega a tiempo, aunque sea lento, no se corta', () async {
      Stream<List<int>> lento() async* {
        for (var i = 0; i < 3; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          yield [i];
        }
      }

      final r = await crear(
        (_) async => http.StreamedResponse(lento(), 200),
        esperaPedazo: const Duration(milliseconds: 500),
      ).pedir(origen, desde: 0);

      expect(await leer(r), [0, 1, 2]);
    });
  });
}
