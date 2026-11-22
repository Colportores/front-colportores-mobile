// El nivel de la batería viene de un canal nativo propio (R-SY10): lo que no se puede saber no
// frena el respaldo.
import 'dart:async';

import 'package:colportores_mobile/features/respaldo/data/services/nivel_bateria_canal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel(NivelBateriaCanal.nombre);

  void responder(Future<Object?> Function(MethodCall) manejador) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      manejador,
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null),
    );
  }

  test('el canal se llama como en Kotlin y en Swift', () {
    expect(NivelBateriaCanal.nombre, 'colportores/bateria');
  });

  test('devuelve el porcentaje que informa el sistema', () async {
    responder((call) async {
      expect(call.method, 'nivel');
      return 42;
    });

    expect(await NivelBateriaCanal().porcentaje(), 42);
  });

  test('sin dato (nulo) o fuera de rango: no sabe', () async {
    responder((_) async => null);
    expect(await NivelBateriaCanal().porcentaje(), isNull);

    responder((_) async => -1);
    expect(await NivelBateriaCanal().porcentaje(), isNull);

    responder((_) async => 140);
    expect(await NivelBateriaCanal().porcentaje(), isNull);
  });

  test('un error del lado nativo no lanza', () async {
    responder((_) async => throw PlatformException(code: 'BATERIA'));

    expect(await NivelBateriaCanal().porcentaje(), isNull);
  });

  test('sin canal registrado (escritorio, tests) no lanza', () async {
    expect(await NivelBateriaCanal().porcentaje(), isNull);
  });

  test('si el sistema no contesta, no cuelga el respaldo', () async {
    responder((_) => Completer<Object?>().future);

    final nivel = await NivelBateriaCanal(
      tiempoMaximo: const Duration(milliseconds: 20),
    ).porcentaje();

    expect(nivel, isNull);
  });

  test('NivelBateriaDesconocido nunca sabe', () async {
    expect(await const NivelBateriaDesconocido().porcentaje(), isNull);
  });
}
