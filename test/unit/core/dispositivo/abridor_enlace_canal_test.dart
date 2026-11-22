import 'dart:async';

import 'package:colportores_mobile/core/config/config_soporte.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_enlace_externo.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('colportores/seguridad_dispositivo');
  final llamadas = <MethodCall>[];

  void responder(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      (call) {
        llamadas.add(call);
        return handler(call);
      },
    );
  }

  setUp(llamadas.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      null,
    );
  });

  group('ConfigSoporte', () {
    test('el enlace abre el chat del +54 3751 530020 (con el 9 de wa.me) y lleva el código', () {
      final enlace = ConfigSoporte.enlaceWhatsapp('DB_ALMACEN_SEGURO');

      expect(enlace.host, 'wa.me');
      expect(enlace.path, '/5493751530020');
      expect(
        enlace.queryParameters['text'],
        'Hola, necesito ayuda con la app Colportores. Código del error: DB_ALMACEN_SEGURO',
      );
      expect(ConfigSoporte.whatsappVisible, '+54 3751 530020');
    });

    test('el número es de la configuración: con otro número, el enlace cambia', () {
      final enlace = ConfigSoporte.enlaceWhatsapp('X', numero: '5491100000000');

      expect(enlace.path, '/5491100000000');
    });
  });

  group('AbridorEnlaceCanal', () {
    final enlace = ConfigSoporte.enlaceWhatsapp('DB_SIN_ESPACIO');

    test('llama a abrirEnlace con la url y devuelve lo que responde el sistema', () async {
      responder((_) async => true);

      expect(await AbridorEnlaceCanal().abrir(enlace), isTrue);
      expect(llamadas.single.method, 'abrirEnlace');
      expect((llamadas.single.arguments as Map)['url'], enlace.toString());
    });

    test('si el sistema no tiene con qué abrirlo, devuelve false', () async {
      responder((_) async => false);

      expect(await AbridorEnlaceCanal().abrir(enlace), isFalse);
    });

    test(
      'una respuesta nula, una PlatformException o la falta del canal (iOS) dan false',
      () async {
        responder((_) async => null);
        expect(await AbridorEnlaceCanal().abrir(enlace), isFalse);

        responder((_) async => throw PlatformException(code: 'X'));
        expect(await AbridorEnlaceCanal().abrir(enlace), isFalse);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          canal,
          null,
        );
        expect(await AbridorEnlaceCanal().abrir(enlace), isFalse);
      },
    );

    test('si el sistema no responde, da false al vencer el tiempo máximo', () async {
      responder((_) => Completer<Object?>().future);

      final abierto = await AbridorEnlaceCanal(
        tiempoMaximo: const Duration(milliseconds: 20),
      ).abrir(enlace);

      expect(abierto, isFalse);
    });
  });
}
