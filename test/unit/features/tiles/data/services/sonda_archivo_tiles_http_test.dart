// Test de data: la prueba del archivo del mapa en línea (#299, «Mapa caído»), con un cliente HTTP
// simulado. Pide 1 byte con Range y no lee el cuerpo, conteste lo que conteste el servidor.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/cliente_descarga_rango_http.dart';
import 'package:colportores_mobile/features/tiles/data/services/sonda_archivo_tiles_http.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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

  group('el pedido se aborta (no queda una conexión abierta)', () {
    /// Un servidor que acepta y no contesta, visto desde un cliente que sabe abortar como el real:
    /// si el pedido es abortable y se aborta, el envío falla con [http.RequestAbortedException].
    Future<http.StreamedResponse> colgado(http.BaseRequest pedido, List<String> eventos) {
      final nunca = Completer<http.StreamedResponse>();
      eventos.add('pedido');
      if (pedido case http.Abortable(:final abortTrigger?)) {
        unawaited(
          abortTrigger.then((_) {
            eventos.add('abortado');
            if (!nunca.isCompleted) nunca.completeError(http.RequestAbortedException(pedido.url));
          }),
        );
      }
      return nunca.future;
    }

    test('el pedido es abortable', () async {
      final r = conCuerpo(206);

      await crear((_) async => r.respuesta).probar(origen);

      expect(enviado, isA<http.Abortable>());
      expect((enviado as http.Abortable).abortTrigger, isNotNull);
    });

    test('al vencer el tiempo se aborta el pedido que quedó colgado', () async {
      final eventos = <String>[];

      await expectLater(
        crear(
          (pedido) => colgado(pedido, eventos),
          esperaRespuesta: const Duration(milliseconds: 20),
        ).probar(origen),
        throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', isA<TimeoutException>())),
      );
      await Future<void>.delayed(Duration.zero);

      expect(eventos, ['pedido', 'abortado']);
    });

    test('al cancelar la prueba se aborta el pedido y no se espera el tiempo', () async {
      final eventos = <String>[];
      final cancelar = Completer<void>();
      final sonda = crear((pedido) => colgado(pedido, eventos));

      final prueba = expectLater(
        sonda.probar(origen, cancelacion: cancelar.future),
        throwsA(
          isA<ErrorRedTiles>().having((e) => e.causa, 'causa', isA<http.RequestAbortedException>()),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(eventos, ['pedido'], reason: 'sigue esperando: nadie cancela todavía');

      cancelar.complete();
      await prueba;

      expect(eventos, ['pedido', 'abortado']);
    });

    test('una cancelación que ya estaba hecha aborta el pedido apenas sale', () async {
      final eventos = <String>[];

      await expectLater(
        crear(
          (pedido) => colgado(pedido, eventos),
        ).probar(origen, cancelacion: Future<void>.value()),
        throwsA(isA<ErrorRedTiles>()),
      );

      expect(eventos, ['pedido', 'abortado']);
    });

    test('cancelar después de que la prueba terminó no aborta nada', () async {
      final cancelar = Completer<void>();
      var abortado = false;
      final sonda = crear((pedido) async {
        if (pedido case http.Abortable(:final abortTrigger?)) {
          unawaited(abortTrigger.then((_) => abortado = true));
        }
        return conCuerpo(206).respuesta;
      });

      await sonda.probar(origen, cancelacion: cancelar.future);
      cancelar.complete();
      await Future<void>.delayed(Duration.zero);

      expect(abortado, isFalse);
    });

    test('una cancelación que falla no rompe la prueba ni queda sin atrapar', () async {
      final r = conCuerpo(206);

      await crear(
        (_) async => r.respuesta,
      ).probar(origen, cancelacion: Future<void>.error(StateError('no debería')));
      await Future<void>.delayed(Duration.zero);

      expect(r.eventos, ['escuchado', 'soltado']);
    });

    test('un aborto justo después de la respuesta no deja un error sin manejar', () async {
      // `package:http` inyecta RequestAbortedException en el cuerpo si se aborta antes de
      // escucharlo: al soltar la respuesta ese error tiene que tener quien lo atrape.
      final cancelar = Completer<void>();
      final sonda = crear((pedido) async {
        final cuerpo = StreamController<List<int>>(sync: true);
        cancelar.complete();
        cuerpo.addError(http.RequestAbortedException(pedido.url));
        return http.StreamedResponse(cuerpo.stream, 206);
      });

      await sonda.probar(origen, cancelacion: cancelar.future);
      await Future<void>.delayed(Duration.zero);
    });

    group('contra un servidor de verdad (loopback, cliente de dart:io)', () {
      late ServerSocket servidor;
      late List<Socket> conexiones;
      late int cerradas;
      late Uri archivo;

      setUp(() async {
        conexiones = [];
        cerradas = 0;
        servidor = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        // Acepta, lee el pedido y no contesta nunca. El cierre del lado del cliente se ve como el
        // fin de la lectura.
        servidor.listen((conexion) {
          conexiones.add(conexion);
          conexion.listen((_) {}, onDone: () => cerradas++, onError: (Object _) => cerradas++);
        });
        archivo = Uri.parse('http://127.0.0.1:${servidor.port}/montevideo.pmtiles');
      });

      tearDown(() async {
        for (final conexion in conexiones) {
          conexion.destroy();
        }
        await servidor.close();
      });

      Future<void> esperarCerradas(int cuantas) async {
        for (var i = 0; i < 100 && cerradas < cuantas; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      test('diez aperturas contra un servidor colgado: las diez conexiones se cierran', () async {
        final cliente = IOClient(HttpClient());
        addTearDown(cliente.close);
        final sonda = SondaArchivoTilesHttp(
          cliente: cliente,
          esperaRespuesta: const Duration(milliseconds: 150),
        );

        for (var i = 0; i < 10; i++) {
          await expectLater(
            sonda.probar(archivo),
            throwsA(isA<ErrorRedTiles>().having((e) => e.causa, 'causa', isA<TimeoutException>())),
          );
        }
        await esperarCerradas(10);

        expect(conexiones, hasLength(10));
        expect(cerradas, 10, reason: 'sin abortar, el cliente las deja abiertas');
      });

      test('salir del mapa (cancelar) cierra la conexión sin esperar los 30 s', () async {
        final cliente = IOClient(HttpClient());
        addTearDown(cliente.close);
        final sonda = SondaArchivoTilesHttp(cliente: cliente);
        final cancelar = Completer<void>();

        final prueba = expectLater(
          sonda.probar(archivo, cancelacion: cancelar.future),
          throwsA(isA<ErrorRedTiles>()),
        );
        for (var i = 0; i < 100 && conexiones.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(conexiones, hasLength(1));
        expect(cerradas, 0, reason: 'mientras nadie cancela, la conexión sigue abierta');

        cancelar.complete();
        await prueba;
        await esperarCerradas(1);

        expect(cerradas, 1);
      });
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
