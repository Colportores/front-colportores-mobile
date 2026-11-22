// Test de data: el canal nativo del espacio libre y de la exclusión del respaldo, con el lado
// nativo simulado.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/features/tiles/data/services/almacenamiento_tiles_canal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel(AlmacenamientoTilesCanal.nombre);
  final directorio = Directory('/data/user/0/uy.colportores/files/tiles');
  final llamadas = <MethodCall>[];

  AlmacenamientoTilesCanal crear({Duration tiempoMaximo = const Duration(seconds: 5)}) {
    return AlmacenamientoTilesCanal(directorio, tiempoMaximo: tiempoMaximo, logger: loggerMudo());
  }

  void nativo(Future<Object?> Function(MethodCall) responder) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      (llamada) {
        llamadas.add(llamada);
        return responder(llamada);
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

  test('el canal se llama igual que del lado de Kotlin y de Swift', () {
    expect(AlmacenamientoTilesCanal.nombre, 'colportores/almacenamiento_tiles');
  });

  group('bytesLibres', () {
    test('le pide al lado nativo el espacio de la carpeta de los paquetes', () async {
      nativo((_) async => 123456789);

      final libres = await crear().bytesLibres();

      expect(libres, 123456789);
      expect(llamadas.single.method, 'bytesLibres');
      expect(llamadas.single.arguments, {'ruta': directorio.path});
    });

    test('un teléfono con el disco lleno informa 0 y no se lo toma por un error', () async {
      nativo((_) async => 0);

      expect(await crear().bytesLibres(), 0);
    });

    test('si la plataforma falla, no frena la descarga: devuelve «sin medida»', () async {
      nativo((_) async => throw PlatformException(code: 'sin_medida'));

      expect(await crear().bytesLibres(), AlmacenamientoTilesCanal.sinMedida);
    });

    test('si la plataforma no tiene el canal (MissingPluginException), tampoco', () async {
      // Sin handler: el mensajero responde que no hay implementación.
      expect(await crear().bytesLibres(), AlmacenamientoTilesCanal.sinMedida);
    });

    test('si contesta algo que no es un número válido, devuelve «sin medida»', () async {
      for (final respuesta in <Object?>[null, -1, 'mucho']) {
        nativo((_) async => respuesta);

        expect(
          await crear().bytesLibres(),
          AlmacenamientoTilesCanal.sinMedida,
          reason: '$respuesta',
        );
      }
    });

    test('si no contesta a tiempo, devuelve «sin medida»', () async {
      final nunca = Completer<Object?>();
      nativo((_) => nunca.future);

      final libres = await crear(tiempoMaximo: const Duration(milliseconds: 20)).bytesLibres();

      expect(libres, AlmacenamientoTilesCanal.sinMedida);
    });

    test('«sin medida» es más que cualquier paquete (~1 GB) y que cualquier disco', () {
      expect(AlmacenamientoTilesCanal.sinMedida, greaterThan(1 << 50));
    });
  });

  group('excluirDeBackup', () {
    test('le pide al lado nativo que saque la carpeta del respaldo', () async {
      nativo((_) async => true);

      await crear().excluirDeBackup();

      expect(llamadas.single.method, 'excluirDeBackup');
      expect(llamadas.single.arguments, {'ruta': directorio.path});
    });

    test('si falla, no lanza: los mapas se pueden usar igual', () async {
      nativo((_) async => throw PlatformException(code: 'no_se_pudo'));

      await expectLater(crear().excluirDeBackup(), completes);
    });

    test('sin el canal nativo tampoco lanza', () async {
      await expectLater(crear().excluirDeBackup(), completes);
    });

    test('si no contesta a tiempo, no lanza', () async {
      final nunca = Completer<Object?>();
      nativo((_) => nunca.future);

      await expectLater(
        crear(tiempoMaximo: const Duration(milliseconds: 20)).excluirDeBackup(),
        completes,
      );
    });
  });
}
