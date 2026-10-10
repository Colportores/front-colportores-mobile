// La app queda fija en vertical (#301, decisión de Cristian del 07/10). Tres lugares dicen lo mismo:
// el arranque (`OrientacionApp.fijarVertical`), el manifest de Android y el `Info.plist` de iOS.
// Los dos archivos nativos no se pueden probar en un teléfono desde Docker: el test los lee, para
// que nadie vuelva a abrir el horizontal sin darse cuenta.
import 'dart:io';

import 'package:colportores_mobile/core/dispositivo/orientacion_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrientacionApp (arranque)', () {
    final llamadas = <MethodCall>[];

    setUp(() {
      llamadas.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          llamadas.add(call);
          return null;
        },
      );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    test('dado el arranque, cuando fija la orientación, pide solo el teléfono derecho', () async {
      await OrientacionApp.fijarVertical();

      expect(llamadas, hasLength(1));
      expect(llamadas.single.method, 'SystemChrome.setPreferredOrientations');
      expect(llamadas.single.arguments, ['DeviceOrientation.portraitUp']);
    });
  });

  group('Orientación en los archivos nativos', () {
    test('Android: toda actividad del manifest lleva android:screenOrientation="portrait"', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      final actividades = RegExp(r'<activity\b[^>]*>').allMatches(manifest).toList();

      expect(actividades, isNotEmpty);
      for (final actividad in actividades) {
        expect(
          actividad.group(0),
          contains('android:screenOrientation="portrait"'),
          reason: 'una actividad sin orientación fija gira con el teléfono',
        );
      }
    });

    test('iOS: iPhone y iPad aceptan solo UIInterfaceOrientationPortrait', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(_orientacionesDe(plist, 'UISupportedInterfaceOrientations'), [
        'UIInterfaceOrientationPortrait',
      ]);
      expect(_orientacionesDe(plist, 'UISupportedInterfaceOrientations~ipad'), [
        'UIInterfaceOrientationPortrait',
      ]);
    });
  });
}

/// Las posiciones que declara el `Info.plist` bajo [clave] (el `<array>` que sigue a la clave).
List<String> _orientacionesDe(String plist, String clave) {
  final arreglo = RegExp(
    '<key>${RegExp.escape(clave)}</key>\\s*<array>(.*?)</array>',
    dotAll: true,
  ).firstMatch(plist);
  expect(arreglo, isNotNull, reason: 'falta $clave en el Info.plist');
  return RegExp(
    r'<string>(.*?)</string>',
  ).allMatches(arreglo!.group(1)!).map((m) => m.group(1)!).toList();
}
