// El adaptador del canal nativo de seguridad del equipo (ADR-006). El lado nativo se simula con un
// handler de mensajes: los tests nunca tocan Kotlin ni Swift.
import 'package:colportores_mobile/core/dispositivo/fakes/seguridad_dispositivo_fija.dart';
import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo.dart';
import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo_canal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel(SeguridadDispositivoCanal.nombre);
  late SeguridadDispositivoCanal seguridad;
  final llamadas = <String>[];

  void responder(Object? Function(MethodCall llamada) respuesta) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      (llamada) async {
        llamadas.add(llamada.method);
        return respuesta(llamada);
      },
    );
  }

  setUp(() {
    llamadas.clear();
    seguridad = SeguridadDispositivoCanal();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      null,
    );
  });

  group('SeguridadDispositivoCanal', () {
    test('el canal se llama igual que en MainActivity.kt y AppDelegate.swift', () {
      expect(SeguridadDispositivoCanal.nombre, 'colportores/seguridad_dispositivo');
    });

    test('dado un equipo con bloqueo de pantalla, lo informa', () async {
      responder((_) => true);

      expect(await seguridad.tieneBloqueoPantalla(), isTrue);
      expect(llamadas, ['bloqueoPantalla']);
    });

    test('dado un equipo sin bloqueo de pantalla, lo informa', () async {
      responder((_) => false);

      expect(await seguridad.tieneBloqueoPantalla(), isFalse);
    });

    test('dado un Keystore por hardware o por software, lo traduce al nivel', () async {
      responder((_) => 'hardware');
      expect(await seguridad.nivelAlmacenSeguro(), NivelAlmacenSeguro.hardware);

      responder((_) => 'software');
      expect(await seguridad.nivelAlmacenSeguro(), NivelAlmacenSeguro.software);
      expect(llamadas, ['nivelAlmacen', 'nivelAlmacen']);
    });

    test('dada una respuesta desconocida, lanza SeguridadDispositivoException', () async {
      responder((_) => 'quién sabe');

      await expectLater(
        seguridad.nivelAlmacenSeguro(),
        throwsA(isA<SeguridadDispositivoException>()),
      );
    });

    test('dada una respuesta vacía, lanza SeguridadDispositivoException', () async {
      responder((_) => null);

      await expectLater(
        seguridad.tieneBloqueoPantalla(),
        throwsA(
          isA<SeguridadDispositivoException>().having(
            (e) => e.operacion,
            'operacion',
            'bloqueoPantalla',
          ),
        ),
      );
    });

    test(
      'dado que la plataforma falla, lanza SeguridadDispositivoException con la causa',
      () async {
        responder((_) => throw PlatformException(code: 'SEGURIDAD_DISPOSITIVO'));

        await expectLater(
          seguridad.nivelAlmacenSeguro(),
          throwsA(
            isA<SeguridadDispositivoException>().having(
              (e) => e.causa,
              'causa',
              isA<PlatformException>(),
            ),
          ),
        );
      },
    );

    test('dado que no hay canal nativo (un entorno sin plataforma), lanza '
        'SeguridadDispositivoException', () async {
      await expectLater(
        seguridad.tieneBloqueoPantalla(),
        throwsA(isA<SeguridadDispositivoException>()),
      );
    });

    test('la excepción solo dice la operación', () {
      expect(
        const SeguridadDispositivoException(operacion: 'nivelAlmacen', causa: 'x').toString(),
        'SeguridadDispositivoException(nivelAlmacen)',
      );
    });
  });

  group('SeguridadDispositivoFija', () {
    test('responde lo configurado, y falla a pedido', () async {
      final fija = SeguridadDispositivoFija(
        bloqueoPantalla: false,
        nivel: NivelAlmacenSeguro.software,
      );

      expect(await fija.tieneBloqueoPantalla(), isFalse);
      expect(await fija.nivelAlmacenSeguro(), NivelAlmacenSeguro.software);

      fija.simularFalla = true;
      await expectLater(fija.tieneBloqueoPantalla(), throwsA(isA<SeguridadDispositivoException>()));
      await expectLater(fija.nivelAlmacenSeguro(), throwsA(isA<SeguridadDispositivoException>()));
    });
  });
}
