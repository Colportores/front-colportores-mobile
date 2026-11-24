// HU-NOT-001 / #414 («Token FCM»): el teléfono sube su token a `usuario.fcm_token` (función del
// servidor), lo vuelve a subir si el sistema lo cambia, y lo vacía al cerrar sesión. Sin Flutter.
import 'dart:async';

import 'package:colportores_mobile/features/notificaciones/data/repositories/token_push_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/token_push_repository.dart';
import 'package:colportores_mobile/features/notificaciones/domain/services/registro_token_push.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

void main() {
  late TokenPushEnMemoria servidor;
  late String? tokenDelSistema;
  late Object? fallaDelSistema;
  late Completer<void>? demoraDelSistema;
  late int pedidosAlSistema;
  late DateTime ahora;
  late RegistroTokenPush registro;

  setUp(() {
    servidor = TokenPushEnMemoria();
    tokenDelSistema = 'token-1';
    fallaDelSistema = null;
    demoraDelSistema = null;
    pedidosAlSistema = 0;
    ahora = DateTime.utc(2026, 11, 22, 10);
    registro = RegistroTokenPush(
      servidor: servidor,
      obtenerToken: () async {
        pedidosAlSistema++;
        await demoraDelSistema?.future;
        if (fallaDelSistema case final f?) throw f;
        return tokenDelSistema;
      },
      ahora: () => ahora,
      logger: loggerMudo(),
    );
  });

  group('subir el token', () {
    test('al dar el permiso, pide el token al sistema y lo sube', () async {
      await registro.sincronizar();

      expect(servidor.pedidos, ['token-1']);
      expect(servidor.guardado, 'token-1');
      expect(registro.subido, 'token-1');
      expect(registro.hayPendiente, isFalse);
    });

    test('un teléfono sin token todavía (sin Firebase) no sube nada ni queda pendiente', () async {
      tokenDelSistema = null;
      await registro.sincronizar();
      tokenDelSistema = '';
      await registro.sincronizar();

      expect(servidor.pedidos, isEmpty);
      expect(registro.hayPendiente, isFalse);
    });

    test('Escenario: Token rotado — sube el token nuevo sin volver a pedirlo al sistema', () async {
      await registro.sincronizar();

      await registro.sincronizar(token: 'token-2');

      expect(servidor.pedidos, ['token-1', 'token-2']);
      expect(servidor.guardado, 'token-2');
      expect(pedidosAlSistema, 1);
    });
  });

  group('sin conexión o con el servidor caído', () {
    test('queda pendiente y se sube cuando hace falta, sin avisar nada', () async {
      servidor.falla = const TokenPushSinConexionException();
      await registro.sincronizar();
      expect(registro.hayPendiente, isTrue);
      expect(servidor.guardado, isNull);

      servidor.falla = null;
      await registro.sincronizarSiHaceFalta();

      expect(servidor.guardado, 'token-1');
      expect(registro.hayPendiente, isFalse);
    });

    test(
      'un error del servidor (sin sesión, token inválido) tampoco lanza: queda pendiente',
      () async {
        servidor.falla = const TokenPushServidorException(codigo: '42501');

        await expectLater(registro.sincronizar(), completes);

        expect(registro.hayPendiente, isTrue);
      },
    );

    test('un error inesperado al subir tampoco tira nada abajo', () async {
      final raro = RegistroTokenPush(
        servidor: _ServidorQueExplota(),
        obtenerToken: () async => 'token-1',
        logger: loggerMudo(),
      );

      await expectLater(raro.sincronizar(), completes);

      expect(raro.hayPendiente, isTrue);
    });

    test(
      'el sistema que no da el token (sin Google Play, iOS sin registrar) deja pendiente',
      () async {
        fallaDelSistema = StateError('apns-token-not-set');
        await registro.sincronizar();
        expect(registro.hayPendiente, isTrue);
        expect(servidor.pedidos, isEmpty);

        fallaDelSistema = null;
        await registro.sincronizarSiHaceFalta();

        expect(servidor.guardado, 'token-1');
        expect(registro.hayPendiente, isFalse);
      },
    );

    test('un token rotado que no se pudo subir se reintenta con el actual', () async {
      await registro.sincronizar();
      servidor.falla = const TokenPushSinConexionException();
      await registro.sincronizar(token: 'token-2');
      expect(registro.hayPendiente, isTrue);

      servidor.falla = null;
      tokenDelSistema = 'token-2';
      await registro.sincronizarSiHaceFalta();

      expect(servidor.guardado, 'token-2');
    });

    test('un sistema que nunca contesta no deja la serie colgada: a los 20 s queda pendiente', () {
      fakeAsync((reloj) {
        final lento = RegistroTokenPush(
          servidor: servidor,
          obtenerToken: () => Completer<String?>().future,
          logger: loggerMudo(),
        );
        var terminado = false;
        unawaited(lento.sincronizar().then((_) => terminado = true));

        reloj.elapse(topeDelToken - const Duration(seconds: 1));
        expect(terminado, isFalse);
        reloj.elapse(const Duration(seconds: 2));

        expect(terminado, isTrue);
        expect(lento.hayPendiente, isTrue);
        expect(servidor.pedidos, isEmpty);
      });
    });
  });

  group('hacer falta o no', () {
    test('recién subido, sincronizarSiHaceFalta no vuelve a subir', () async {
      await registro.sincronizar();

      await registro.sincronizarSiHaceFalta();
      await registro.sincronizarSiHaceFalta();

      expect(servidor.pedidos, ['token-1']);
      expect(pedidosAlSistema, 1);
    });

    test('pasadas 24 h sin confirmarlo, lo repasa en silencio', () async {
      await registro.sincronizar();

      ahora = ahora.add(const Duration(hours: 23, minutes: 59));
      await registro.sincronizarSiHaceFalta();
      expect(servidor.pedidos, hasLength(1));

      ahora = ahora.add(const Duration(minutes: 2));
      await registro.sincronizarSiHaceFalta();
      expect(servidor.pedidos, ['token-1', 'token-1']);
    });

    test('si nunca se subió (sesión nueva), sincronizarSiHaceFalta sube', () async {
      await registro.sincronizarSiHaceFalta();

      expect(servidor.guardado, 'token-1');
    });
  });

  group('dos pedidos seguidos no se pisan ni se pierden', () {
    test(
      'un token rotado mientras otro sube: terminan los dos, en orden, y gana el último',
      () async {
        servidor.demorado = Completer<void>();
        final primera = registro.sincronizar(token: 'a');
        await pumpEventQueue();
        expect(servidor.pedidos, ['a']);

        final segunda = registro.sincronizar(token: 'b');
        await pumpEventQueue();
        expect(servidor.pedidos, ['a'], reason: 'una sola subida a la vez');

        servidor.demorado!.complete();
        await Future.wait([primera, segunda]);

        expect(servidor.pedidos, ['a', 'b']);
        expect(servidor.guardado, 'b');
      },
    );

    test('tres rotaciones mientras una sube: se sube solo la última', () async {
      servidor.demorado = Completer<void>();
      final a = registro.sincronizar(token: 'a');
      await pumpEventQueue();
      final b = registro.sincronizar(token: 'b');
      final c = registro.sincronizar(token: 'c');

      servidor.demorado!.complete();
      await Future.wait([a, b, c]);

      expect(servidor.pedidos, ['a', 'c']);
      expect(servidor.guardado, 'c');
    });

    test('doble toque en «Activar» (dos sincronizar seguidos): una sola subida', () async {
      final a = registro.sincronizar();
      final b = registro.sincronizar();
      await Future.wait([a, b]);

      // El segundo pedido, mientras el primero corría, pide otra vuelta; el token es el mismo.
      expect(servidor.guardado, 'token-1');
      expect(pedidosAlSistema, lessThanOrEqualTo(2));
    });

    test('la falla de una subida no traba la siguiente (nada queda «ocupado»)', () async {
      servidor.falla = const TokenPushSinConexionException();
      await registro.sincronizar();

      servidor.falla = null;
      await registro.sincronizar();

      expect(servidor.guardado, 'token-1');
    });
  });

  group('al cerrar sesión', () {
    test('Escenario: logout — manda el token vacío', () async {
      await registro.sincronizar();

      await registro.retirar();

      expect(servidor.pedidos, ['token-1', null]);
      expect(servidor.guardado, isNull);
    });

    test('sin conexión no lanza ni demora el cierre: el token queda donde estaba', () async {
      await registro.sincronizar();
      servidor.falla = const TokenPushSinConexionException();

      await expectLater(registro.retirar(), completes);

      expect(servidor.guardado, 'token-1');
    });

    test('espera la subida en curso: un token tardío no queda puesto después del vacío', () async {
      servidor.demorado = Completer<void>();
      final subiendo = registro.sincronizar();
      await pumpEventQueue();

      final retiro = registro.retirar();
      await pumpEventQueue();
      expect(servidor.pedidos, ['token-1'], reason: 'el vacío espera a que termine la subida');

      servidor.demorado!.complete();
      await Future.wait([subiendo, retiro]);

      expect(servidor.pedidos, ['token-1', null]);
      expect(servidor.guardado, isNull);
    });

    test('si el servidor no contesta, el cierre espera solo 3 s', () {
      fakeAsync((reloj) {
        servidor.demorado = Completer<void>();
        var terminado = false;
        unawaited(registro.retirar().then((_) => terminado = true));

        reloj.elapse(topeDelRetiro - const Duration(milliseconds: 100));
        expect(terminado, isFalse);
        reloj.elapse(const Duration(milliseconds: 200));

        expect(terminado, isTrue);
      });
    });

    test('mientras se retira, una rotación no vuelve a poner el token', () async {
      await registro.sincronizar();
      servidor.demorado = Completer<void>();
      final retiro = registro.retirar();
      await pumpEventQueue();

      await registro.sincronizar(token: 'token-2');
      servidor.demorado!.complete();
      await retiro;

      expect(servidor.pedidos, ['token-1', null]);
    });

    test('si el cierre no llegó a cerrar la sesión, el teléfono vuelve a registrarse', () async {
      await registro.sincronizar();
      await registro.retirar();
      expect(servidor.guardado, isNull);

      await registro.sincronizarSiHaceFalta();

      expect(servidor.guardado, 'token-1');
    });
  });
}

final class _ServidorQueExplota implements TokenPushRepository {
  @override
  Future<void> registrar(String? token) async => throw StateError('contra el contrato');
}
