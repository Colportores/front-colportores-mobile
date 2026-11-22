import 'dart:async';

import 'package:colportores_mobile/core/dispositivo/abridor_ajustes_sistema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('colportores/seguridad_dispositivo');
  final llamadas = <String>[];

  void responder(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      (call) {
        llamadas.add(call.method);
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

  test(
    'abrirSeguridad y abrirAlmacenamiento llaman a su método y devuelven lo que responde',
    () async {
      responder((_) async => true);
      final abridor = AbridorAjustesCanal();

      expect(await abridor.abrirSeguridad(), isTrue);
      expect(await abridor.abrirAlmacenamiento(), isTrue);
      expect(llamadas, ['abrirAjustesSeguridad', 'abrirAjustesAlmacenamiento']);
    },
  );

  test('una respuesta vacía o falsa es false', () async {
    responder((_) async => null);
    expect(await AbridorAjustesCanal().abrirSeguridad(), isFalse);
    responder((_) async => false);
    expect(await AbridorAjustesCanal().abrirSeguridad(), isFalse);
  });

  test('una falla de la plataforma no lanza: devuelve false', () async {
    responder((_) async => throw PlatformException(code: 'X'));
    expect(await AbridorAjustesCanal().abrirAlmacenamiento(), isFalse);
  });

  test('sin implementación nativa (iOS) devuelve false', () async {
    responder((_) async => throw MissingPluginException());
    expect(await AbridorAjustesCanal().abrirSeguridad(), isFalse);
  });

  test('si la plataforma no contesta a tiempo devuelve false', () async {
    responder((_) => Completer<Object?>().future);
    final abridor = AbridorAjustesCanal(tiempoMaximo: const Duration(milliseconds: 50));

    expect(await abridor.abrirSeguridad(), isFalse);
  });
}
