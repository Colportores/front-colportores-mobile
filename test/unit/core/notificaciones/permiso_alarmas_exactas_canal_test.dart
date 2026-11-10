// «Aviso exacto» (HU-NOT-002, #510): lo que Dart entiende de lo que contestan MainActivity.kt y
// AppDelegate.swift sobre «Alarmas y recordatorios», por el mismo canal `colportores/notificaciones`, y
// que toda falla de la plataforma sale como `PermisoAlarmasExactasException`.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_alarmas_exactas.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mensajeros = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const canal = MethodChannel(PermisoNotificacionesCanal.nombre);

  void responder(Future<Object?>? Function(MethodCall llamada) respuesta) {
    mensajeros.setMockMethodCallHandler(canal, respuesta);
    addTearDown(() => mensajeros.setMockMethodCallHandler(canal, null));
  }

  group('estado', () {
    for (final (texto, esperado) in [
      ('permitidas', EstadoAlarmasExactas.permitidas),
      ('apagadas', EstadoAlarmasExactas.apagadas),
      ('noAplica', EstadoAlarmasExactas.noAplica),
    ]) {
      test('dado que el teléfono contesta «$texto», es $esperado', () async {
        final llamadas = <String>[];
        responder((llamada) async {
          llamadas.add(llamada.method);
          return texto;
        });

        expect(await PermisoAlarmasExactasCanal().leerEstado(), esperado);
        expect(llamadas, ['alarmasExactas']);
      });
    }

    test('una respuesta que no es ninguno de los tres estados es una falla', () async {
      responder((_) async => 'quizas');

      expect(
        PermisoAlarmasExactasCanal().leerEstado(),
        throwsA(isA<PermisoAlarmasExactasException>()),
      );
    });

    test('sin respuesta (null) es una falla', () async {
      responder((_) async => null);

      expect(
        PermisoAlarmasExactasCanal().leerEstado(),
        throwsA(isA<PermisoAlarmasExactasException>()),
      );
    });

    test('un error de la plataforma sale como PermisoAlarmasExactasException', () async {
      responder((_) async => throw PlatformException(code: 'NOTIFICACIONES'));

      expect(
        PermisoAlarmasExactasCanal().leerEstado(),
        throwsA(isA<PermisoAlarmasExactasException>()),
      );
    });

    test('un teléfono sin el método (MissingPluginException) sale como falla propia', () async {
      responder((_) async => throw MissingPluginException());

      expect(
        PermisoAlarmasExactasCanal().leerEstado(),
        throwsA(isA<PermisoAlarmasExactasException>()),
      );
    });

    test('si el teléfono no contesta a tiempo, es una falla y no se cuelga', () async {
      final nunca = Completer<Object?>();
      responder((_) => nunca.future);

      await expectLater(
        PermisoAlarmasExactasCanal(tiempoMaximo: const Duration(milliseconds: 20)).leerEstado(),
        throwsA(isA<PermisoAlarmasExactasException>()),
      );
    });
  });

  group('abrirAjustes', () {
    test('pide «abrirAjustesAlarmas» y devuelve si pudo abrirlos', () async {
      final llamadas = <String>[];
      responder((llamada) async {
        llamadas.add(llamada.method);
        return true;
      });

      expect(await PermisoAlarmasExactasCanal().abrirAjustes(), isTrue);
      expect(llamadas, ['abrirAjustesAlarmas']);
    });

    test('si el teléfono no pudo abrirlos devuelve false', () async {
      responder((_) async => false);

      expect(await PermisoAlarmasExactasCanal().abrirAjustes(), isFalse);
    });

    test('un error de la plataforma sale como PermisoAlarmasExactasException', () async {
      responder((_) async => throw PlatformException(code: 'NOTIFICACIONES'));

      expect(
        PermisoAlarmasExactasCanal().abrirAjustes(),
        throwsA(isA<PermisoAlarmasExactasException>()),
      );
    });
  });
}
