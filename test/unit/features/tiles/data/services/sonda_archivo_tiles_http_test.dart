// Test de data: la prueba del archivo del mapa en línea (#299, «Mapa caído»), con un cliente HTTP
// simulado. Pide 1 byte con Range y no lee el cuerpo, conteste lo que conteste el servidor.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/cliente_descarga_rango_http.dart';
import 'package:colportores_mobile/features/tiles/data/services/sonda_archivo_tiles_http.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final origen = Uri.parse(
    'https://x.supabase.co/storage/v1/object/public/mapas/montevideo.pmtiles',
  );
  late http.BaseRequest enviado;

  SondaArchivoTilesHttp crear(
    Future<http.StreamedResponse> Function(http.BaseRequest) responder, {
    Duration esperaRespuesta = const Duration(seconds: 5),
  }) {
    return SondaArchivoTilesHttp(
      cliente: MockClient.streaming((pedido, _) {
        enviado = pedido;
        return responder(pedido);
      }),
      esperaRespuesta: esperaRespuesta,
    );
  }

  /// Una respuesta cuyo cuerpo no se lee: cuenta si alguien lo escuchó y si lo soltó.
  ({http.StreamedResponse respuesta, List<String> eventos}) conCuerpo(
    int status, [
    Map<String, String> encabezados = const {},
  ]) {
    final eventos = <String>[];
    final cuerpo = StreamController<List<int>>(
      onListen: () => eventos.add('escuchado'),
      onCancel: () => eventos.add('soltado'),
    );
    final respuesta = http.StreamedResponse(cuerpo.stream, status, headers: encabezados);
    return (respuesta: respuesta, eventos: eventos);
  }

  group('el pedido', () {
    test('es un GET al archivo con Range: bytes=0-0 (1 byte) y sin compresión', () async {
      final r = conCuerpo(206, {'content-range': 'bytes 0-0/52428800'});

      await crear((_) async => r.respuesta).probar(origen);

      expect(enviado.method, 'GET');
      expect(enviado.url, origen);
      expect(enviado.headers['range'], 'bytes=0-0');
      expect(enviado.headers['accept-encoding'], 'identity');
    });

    test('espera lo mismo que el descargador, por defecto 30 s', () {
      final cliente = MockClient((_) async => http.Response('', 200));

      expect(
        SondaArchivoTilesHttp(cliente: cliente).esperaRespuesta,
        ClienteDescargaRangoHttp(cliente: cliente).esperaRespuesta,
      );
      expect(SondaArchivoTilesHttp(cliente: cliente).esperaRespuesta, const Duration(seconds: 30));
    });
  });

  group('un servidor que contesta bien', () {
    test('un 206 es una respuesta buena y no se lee el cuerpo', () async {
      final r = conCuerpo(206, {'content-range': 'bytes 0-0/52428800'});

      await crear((_) async => r.respuesta).probar(origen);

      expect(r.eventos, ['escuchado', 'soltado']);
    });

    test('un 200 (el servidor ignoró el Range y manda el archivo entero) también, y se corta '
        'sin bajarlo', () async {
      var pedazosPedidos = 0;
      // Un archivo de 50 MB que el servidor empezaría a mandar: nunca se lo lee.
      Stream<List<int>> archivoEntero() async* {
        for (var i = 0; i < 50; i++) {
          pedazosPedidos++;
          yield List.filled(1000000, 7);
        }
      }

      await crear((_) async => http.StreamedResponse(archivoEntero(), 200)).probar(origen);

      expect(pedazosPedidos, lessThanOrEqualTo(1));
    });

    test(
      'un 206 sin Content-Range sigue siendo una respuesta: la prueba no mira el cuerpo',
      () async {
        await crear((_) async => conCuerpo(206).respuesta).probar(origen);
      },
    );
  });

  group('un servidor que contesta mal', () {
    test(
      'cualquier otro código es un ErrorServidorTiles, incluido el 404 del archivo borrado',
      () async {
        for (final status in [301, 400, 403, 404, 416, 500, 502, 503]) {
          final r = conCuerpo(status);

          await expectLater(
            crear((_) async => r.respuesta).probar(origen),
            throwsA(isA<ErrorServidorTiles>().having((e) => e.status, 'status', status)),
            reason: '$status',
          );
          expect(r.eventos, ['escuchado', 'soltado'], reason: 'el cuerpo del $status se suelta');
        }
      },
    );
  });

  group('la red', () {
    test('sin conexión, DNS o TLS antes de la respuesta es un ErrorRedTiles', () async {
      for (final error in <Object>[
        const SocketException('sin ruta'),
        http.ClientException('cortado'),
        const HandshakeException('tls'),
      ]) {
        await expectLater(
          crear((_) async => throw error).probar(origen),
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
        ).probar(origen),
        throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', isA<TimeoutException>())),
      );
    });

    test(
      'si la respuesta llega después del tiempo, se suelta: no queda la conexión abierta',
      () async {
        final tarde = Completer<http.StreamedResponse>();
        final r = conCuerpo(200);

        await expectLater(
          crear(
            (_) => tarde.future,
            esperaRespuesta: const Duration(milliseconds: 20),
          ).probar(origen),
          throwsA(isA<ErrorRedTiles>()),
        );
        expect(r.eventos, isEmpty);

        tarde.complete(r.respuesta);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(r.eventos, ['escuchado', 'soltado']);
      },
    );

    test('si después del tiempo el cliente falla, no queda un error sin atrapar', () async {
      final tarde = Completer<http.StreamedResponse>();

      await expectLater(
        crear(
          (_) => tarde.future,
          esperaRespuesta: const Duration(milliseconds: 20),
        ).probar(origen),
        throwsA(isA<ErrorRedTiles>()),
      );
      tarde.completeError(const SocketException('cortado tarde'));
      await Future<void>.delayed(Duration.zero);
    });

    test('un error de programación no se disfraza de falla de red', () async {
      await expectLater(
        crear((_) async => throw StateError('bug')).probar(origen),
        throwsStateError,
      );
    });
  });

  test('si no se puede soltar el cuerpo, la respuesta buena sigue siendo buena', () async {
    final cuerpo = StreamController<List<int>>(
      onCancel: () => Future<void>.error(StateError('no se cierra')),
    );

    await crear((_) async => http.StreamedResponse(cuerpo.stream, 206)).probar(origen);
  });

  test('si no se puede soltar el cuerpo, un 404 sigue siendo un 404', () async {
    final cuerpo = StreamController<List<int>>(
      onCancel: () => Future<void>.error(StateError('no se cierra')),
    );

    await expectLater(
      crear((_) async => http.StreamedResponse(cuerpo.stream, 404)).probar(origen),
      throwsA(isA<ErrorServidorTiles>().having((e) => e.status, 'status', 404)),
    );
  });
}
