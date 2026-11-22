import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/push_remotas.dart';
import 'package:colportores_mobile/core/notificaciones/push_remotas_firebase.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las fuentes del plugin, a mano: lo que `firebase_messaging` entregaría en el teléfono.
final class _Plugin {
  _Plugin({this.inicial, this.demora, this.falla});

  final alFrente = StreamController<RemoteMessage>.broadcast();
  // Las del plugin real son de difusión; esta no, para probar que el adaptador cumple el puerto igual.
  final tocadas = StreamController<RemoteMessage>();
  RemoteMessage? inicial;
  Completer<void>? demora;
  Object? falla;
  var consultasInicial = 0;

  Future<RemoteMessage?> laQueAbrioLaApp() async {
    consultasInicial++;
    if (demora case final d?) await d.future;
    if (falla case final f?) throw f;
    return inicial;
  }

  PushRemotasFirebase adaptador() => PushRemotasFirebase(
    alFrente: alFrente.stream,
    tocadas: tocadas.stream,
    laQueAbrioLaApp: laQueAbrioLaApp,
  );

  // Sin await: una fuente que no es de difusión y nadie escuchó no termina nunca de cerrarse.
  void cerrar() {
    unawaited(alFrente.close());
    unawaited(tocadas.close());
  }
}

const _autorizado = {
  'type': 'PEDIDO_AUTORIZADO',
  'event_id': '6f1c1a3e-6b8e-4f4f-9a51-2d1f0b7f6d10',
  'pedido_id': '0b9d7a52-1c55-4a8e-9bd2-6c3c1c9f3e21',
};

void main() {
  group('PushRemotasFirebase: la push que llega con la app abierta', () {
    test(
      'dado un mensaje de onMessage, cuando llega, entonces sale por conLaAppAbierta con su data',
      () async {
        final plugin = _Plugin();
        addTearDown(plugin.cerrar);
        final push = plugin.adaptador();
        final recibidas = <MensajePush>[];
        final sub = push.conLaAppAbierta.listen(recibidas.add);
        addTearDown(sub.cancel);

        plugin.alFrente.add(const RemoteMessage(data: _autorizado));
        await pumpEventQueue();

        expect(recibidas.map((m) => m.datos), [_autorizado]);
      },
    );

    test(
      'dado el título fijo del servidor, cuando llega, entonces el mensaje lleva solo la data',
      () async {
        final plugin = _Plugin();
        addTearDown(plugin.cerrar);
        final push = plugin.adaptador();
        final recibida = push.conLaAppAbierta.first;

        plugin.alFrente.add(
          const RemoteMessage(
            data: _autorizado,
            notification: RemoteNotification(title: 'Te autorizaron un pedido'),
          ),
        );

        expect((await recibida).datos, _autorizado);
      },
    );

    test('dadas dos push seguidas, cuando llegan, entonces salen las dos y en orden', () async {
      final plugin = _Plugin();
      addTearDown(plugin.cerrar);
      final push = plugin.adaptador();
      final recibidas = <MensajePush>[];
      final sub = push.conLaAppAbierta.listen(recibidas.add);
      addTearDown(sub.cancel);

      plugin.alFrente
        ..add(const RemoteMessage(data: {'type': 'A', 'event_id': '1'}))
        ..add(const RemoteMessage(data: {'type': 'B', 'event_id': '2'}));
      await pumpEventQueue();

      expect(recibidas.map((m) => m.datos['event_id']), ['1', '2']);
    });

    test('dada la data del mensaje, cuando se lee, entonces es una copia', () async {
      final plugin = _Plugin();
      addTearDown(plugin.cerrar);
      final push = plugin.adaptador();
      final original = <String, dynamic>{..._autorizado};
      final recibida = push.conLaAppAbierta.first;

      plugin.alFrente.add(RemoteMessage(data: original));
      final mensaje = await recibida;
      original['type'] = 'OTRO';

      expect(mensaje.datos['type'], 'PEDIDO_AUTORIZADO');
    });
  });

  group('PushRemotasFirebase: el toque con la app en segundo plano', () {
    test('dado un toque (onMessageOpenedApp), cuando llega, entonces sale por tocadas y no por '
        'conLaAppAbierta', () async {
      final plugin = _Plugin();
      addTearDown(plugin.cerrar);
      final push = plugin.adaptador();
      final alFrente = <MensajePush>[];
      final tocadas = <MensajePush>[];
      final s1 = push.conLaAppAbierta.listen(alFrente.add);
      final s2 = push.tocadas.listen(tocadas.add);
      addTearDown(s1.cancel);
      addTearDown(s2.cancel);

      plugin.tocadas.add(const RemoteMessage(data: _autorizado));
      await pumpEventQueue();

      expect(tocadas.map((m) => m.datos), [_autorizado]);
      expect(alFrente, isEmpty);
    });

    test('dada una fuente que no es de difusión, cuando se escucha dos veces (la raíz se rearma), '
        'entonces no falla y el segundo oyente recibe', () async {
      final plugin = _Plugin();
      addTearDown(plugin.cerrar);
      final push = plugin.adaptador();
      expect(push.tocadas.isBroadcast, isTrue);
      expect(push.conLaAppAbierta.isBroadcast, isTrue);

      final primera = push.tocadas.listen((_) {});
      await primera.cancel();
      final recibidas = <MensajePush>[];
      final segunda = push.tocadas.listen(recibidas.add);
      addTearDown(segunda.cancel);

      plugin.tocadas.add(const RemoteMessage(data: _autorizado));
      await pumpEventQueue();

      expect(recibidas, hasLength(1));
    });
  });

  group('PushRemotasFirebase: la push que abrió la app desde cerrada', () {
    test(
      'dado que un toque abrió la app, cuando se pregunta, entonces la devuelve una sola vez',
      () async {
        final plugin = _Plugin(inicial: const RemoteMessage(data: _autorizado));
        addTearDown(plugin.cerrar);
        final push = plugin.adaptador();

        expect((await push.tomarLaQueAbrioLaApp())?.datos, _autorizado);
        expect(await push.tomarLaQueAbrioLaApp(), isNull);
        // El plugin puede devolver el mismo mensaje en cada llamada: no se le vuelve a preguntar.
        expect(plugin.consultasInicial, 1);
      },
    );

    test('dadas dos preguntas seguidas antes de que conteste el plugin, entonces solo una se lleva '
        'el mensaje', () async {
      final demora = Completer<void>();
      final plugin = _Plugin(
        inicial: const RemoteMessage(data: _autorizado),
        demora: demora,
      );
      addTearDown(plugin.cerrar);
      final push = plugin.adaptador();

      final primera = push.tomarLaQueAbrioLaApp();
      final segunda = push.tomarLaQueAbrioLaApp();
      demora.complete();

      expect((await primera)?.datos, _autorizado);
      expect(await segunda, isNull);
      expect(plugin.consultasInicial, 1);
    });

    test('dado que la app se abrió de otra manera, cuando se pregunta, entonces es null', () async {
      final plugin = _Plugin();
      addTearDown(plugin.cerrar);
      final push = plugin.adaptador();

      expect(await push.tomarLaQueAbrioLaApp(), isNull);
      expect(await push.tomarLaQueAbrioLaApp(), isNull);
      expect(plugin.consultasInicial, 1);
    });

    test(
      'dado que el plugin falla al leerla, cuando se pregunta, entonces el error sube (lo registra '
      'quien escucha) y no se reintenta',
      () async {
        final plugin = _Plugin(falla: StateError('canal caído'));
        addTearDown(plugin.cerrar);
        final push = plugin.adaptador();

        await expectLater(push.tomarLaQueAbrioLaApp(), throwsStateError);
        expect(await push.tomarLaQueAbrioLaApp(), isNull);
        expect(plugin.consultasInicial, 1);
      },
    );
  });

  group('PushRemotasFirebase.iniciar', () {
    test('dado un build sin la configuración de Firebase, cuando arranca, entonces devuelve null '
        '(la app sigue con el fake)', () async {
      var creadas = 0;
      final push = await PushRemotasFirebase.iniciar(
        inicializar: () async => throw Exception('[core/no-app] sin google-services.json'),
        crear: () {
          creadas++;
          return _Plugin().adaptador();
        },
      );

      expect(push, isNull);
      expect(creadas, 0);
    });

    test('dado que Firebase arranca, cuando arranca, entonces devuelve el adaptador', () async {
      final adaptador = _Plugin().adaptador();
      var inicializado = false;
      final push = await PushRemotasFirebase.iniciar(
        inicializar: () async => inicializado = true,
        crear: () {
          expect(inicializado, isTrue, reason: 'el adaptador se crea con Firebase ya inicializado');
          return adaptador;
        },
      );

      expect(push, same(adaptador));
    });

    test('dado que crear el adaptador falla, cuando arranca, entonces devuelve null', () async {
      final push = await PushRemotasFirebase.iniciar(
        inicializar: () async {},
        crear: () => throw StateError('sin plugin'),
      );

      expect(push, isNull);
    });
  });
}
