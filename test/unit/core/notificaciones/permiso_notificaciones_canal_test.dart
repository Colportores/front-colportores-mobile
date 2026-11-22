// El canal nativo `colportores/notificaciones` (HU-NOT-001, vista 24): lo que Dart entiende de lo que
// contestan MainActivity.kt y AppDelegate.swift, y que toda falla de la plataforma sale como
// `PermisoNotificacionesException`.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mensajeros = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const nombre = PermisoNotificacionesCanal.nombre;

  void responder(Future<Object?>? Function(MethodCall llamada) respuesta) {
    mensajeros.setMockMethodCallHandler(const MethodChannel(nombre), respuesta);
    addTearDown(() => mensajeros.setMockMethodCallHandler(const MethodChannel(nombre), null));
  }

  test('el canal se llama como en Kotlin y en Swift', () {
    expect(PermisoNotificacionesCanal.nombre, 'colportores/notificaciones');
  });

  group('estado', () {
    for (final (texto, esperado) in [
      ('activadas', EstadoSistemaNotificaciones.activadas),
      ('sinPreguntar', EstadoSistemaNotificaciones.sinPreguntar),
      ('apagadas', EstadoSistemaNotificaciones.apagadas),
    ]) {
      test('dado que el teléfono contesta «$texto», es $esperado', () async {
        responder((llamada) async => llamada.method == 'estado' ? texto : null);

        expect(await PermisoNotificacionesCanal().leerEstado(), esperado);
      });
    }

    test('una respuesta que no es ninguno de los tres estados es una falla', () async {
      responder((_) async => 'quizas');

      expect(
        PermisoNotificacionesCanal().leerEstado(),
        throwsA(isA<PermisoNotificacionesException>()),
      );
    });

    test('sin respuesta (null) es una falla', () async {
      responder((_) async => null);

      expect(
        PermisoNotificacionesCanal().leerEstado(),
        throwsA(isA<PermisoNotificacionesException>()),
      );
    });

    test('un error de la plataforma sale como PermisoNotificacionesException', () async {
      responder((_) async => throw PlatformException(code: 'NOTIFICACIONES'));

      expect(
        PermisoNotificacionesCanal().leerEstado(),
        throwsA(
          isA<PermisoNotificacionesException>().having((e) => e.operacion, 'operacion', 'estado'),
        ),
      );
    });

    test('un teléfono sin el canal (MissingPluginException) también es una falla', () async {
      expect(
        PermisoNotificacionesCanal().leerEstado(),
        throwsA(isA<PermisoNotificacionesException>()),
      );
    });

    test('si la plataforma no contesta a tiempo, es una falla y no cuelga', () async {
      final nunca = Completer<Object?>();
      responder((_) => nunca.future);

      await expectLater(
        PermisoNotificacionesCanal(tiempoMaximo: const Duration(milliseconds: 20)).leerEstado(),
        throwsA(isA<PermisoNotificacionesException>()),
      );
    });
  });

  group('pedir', () {
    test('devuelve si quedaron activadas, y espera lo que tarde la persona en contestar', () async {
      final respuesta = Completer<Object?>();
      responder((llamada) => llamada.method == 'pedir' ? respuesta.future : Future.value());

      var termino = false;
      final pedido = PermisoNotificacionesCanal(
        tiempoMaximo: const Duration(milliseconds: 20),
      ).pedir().then((v) => termino = v);

      // Más que el tope de las otras llamadas: el diálogo del sistema no tiene tope.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(termino, isFalse);

      respuesta.complete(true);
      await pedido;
      expect(termino, isTrue);
    });

    test('«No permitir» llega como false', () async {
      responder((_) async => false);

      expect(await PermisoNotificacionesCanal().pedir(), isFalse);
    });

    test('un error de la plataforma sale como PermisoNotificacionesException', () async {
      responder((_) async => throw PlatformException(code: 'NOTIFICACIONES', message: 'EnCurso'));

      expect(
        PermisoNotificacionesCanal().pedir(),
        throwsA(
          isA<PermisoNotificacionesException>().having((e) => e.operacion, 'operacion', 'pedir'),
        ),
      );
    });
  });

  group('abrirAjustes', () {
    test('devuelve si pudo abrirlos', () async {
      responder((llamada) async => llamada.method == 'abrirAjustes');

      expect(await PermisoNotificacionesCanal().abrirAjustes(), isTrue);
    });

    test('un teléfono que no los abre contesta false', () async {
      responder((_) async => false);

      expect(await PermisoNotificacionesCanal().abrirAjustes(), isFalse);
    });

    test('un error de la plataforma sale como PermisoNotificacionesException', () async {
      responder((_) async => throw PlatformException(code: 'NOTIFICACIONES'));

      expect(
        PermisoNotificacionesCanal().abrirAjustes(),
        throwsA(isA<PermisoNotificacionesException>()),
      );
    });
  });

  test('el toString de la excepción no lleva la causa', () {
    expect(
      const PermisoNotificacionesException(operacion: 'pedir', causa: 'detalle interno').toString(),
      'PermisoNotificacionesException(pedir)',
    );
  });
}
