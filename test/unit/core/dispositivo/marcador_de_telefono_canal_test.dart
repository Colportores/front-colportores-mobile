import 'dart:async';

import 'package:colportores_mobile/core/dispositivo/marcador_de_telefono_canal.dart';
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

  group('MarcadorDeTelefonoCanal', () {
    test('llama a marcarTelefono con el número y devuelve lo que responde el sistema', () async {
      responder((_) async => true);

      expect(await MarcadorDeTelefonoCanal().marcar('+59899123456'), isTrue);
      expect(llamadas.single.method, 'marcarTelefono');
      expect((llamadas.single.arguments as Map)['numero'], '+59899123456');
    });

    test('si el sistema no tiene con qué marcar, devuelve false', () async {
      responder((_) async => false);

      expect(await MarcadorDeTelefonoCanal().marcar('099123456'), isFalse);
    });

    test(
      'una respuesta nula, una PlatformException o la falta del canal (iOS) dan false',
      () async {
        responder((_) async => null);
        expect(await MarcadorDeTelefonoCanal().marcar('099123456'), isFalse);

        responder((_) async => throw PlatformException(code: 'X'));
        expect(await MarcadorDeTelefonoCanal().marcar('099123456'), isFalse);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          canal,
          null,
        );
        expect(await MarcadorDeTelefonoCanal().marcar('099123456'), isFalse);
      },
    );

    test('si el sistema no responde, da false al vencer el tiempo máximo', () async {
      responder((_) => Completer<Object?>().future);

      final abierto = await MarcadorDeTelefonoCanal(
        tiempoMaximo: const Duration(milliseconds: 20),
      ).marcar('099123456');

      expect(abierto, isFalse);
    });
  });
}
