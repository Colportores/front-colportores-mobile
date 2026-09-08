// Test de la custodia de la sal: Dart puro, con el almacén seguro en memoria.
import 'dart:convert';

import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

/// Logger mudo para no ensuciar la salida de los tests.
AppLogger _loggerMudo() => AppLogger(logger: Logger(level: Level.off));

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late CustodiaClaveDb custodia;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    custodia = CustodiaClaveDb(almacen, logger: _loggerMudo());
  });

  group('CustodiaClaveDb.leerSal', () {
    group('dado un dispositivo nuevo', () {
      test('cuando lee la sal, devuelve null', () async {
        expect(await custodia.leerSal(), isNull);
      });
    });

    group('dado que ya se generó una sal', () {
      test('cuando la lee, devuelve exactamente los bytes generados', () async {
        final generada = await custodia.generarSal();

        expect(await custodia.leerSal(), generada);
      });
    });

    group('dado que lo guardado no es una sal válida', () {
      test('cuando no es base64, lanza SalCorruptaException', () async {
        await almacen.escribir(ClaveSegura.salDb, 'no es base64!!');

        await expectLater(custodia.leerSal(), throwsA(isA<SalCorruptaException>()));
      });

      test('cuando tiene otro largo, lanza SalCorruptaException', () async {
        await almacen.escribir(ClaveSegura.salDb, base64Encode(List<int>.filled(16, 0)));

        await expectLater(custodia.leerSal(), throwsA(isA<SalCorruptaException>()));
      });
    });
  });

  group('CustodiaClaveDb.generarSal', () {
    test('cuando genera, la sal tiene los 256 bits de ADR-003', () async {
      final sal = await custodia.generarSal();

      expect(sal, hasLength(32));
      expect(CustodiaClaveDb.bytesDeSal, 32);
    });

    test('cuando genera, la persiste en el almacén seguro codificada en base64', () async {
      final sal = await custodia.generarSal();

      expect(base64Decode(almacen.contenido[ClaveSegura.salDb]!), sal);
    });

    test('cuando genera dos veces, las sales son distintas y no quedan en cero', () async {
      final primera = await custodia.generarSal();
      final segunda = await custodia.generarSal();

      expect(segunda, isNot(primera), reason: 'la sal no puede ser predecible');
      expect(primera.every((b) => b == 0), isFalse);
    });

    test('cuando reintenta una inicialización fallida, reemplaza la sal anterior', () async {
      final primera = await custodia.generarSal();

      final segunda = await custodia.generarSal();

      expect(await custodia.leerSal(), segunda);
      expect(await custodia.leerSal(), isNot(primera));
    });

    group('dado que la DB del dispositivo ya está inicializada', () {
      setUp(() async {
        await custodia.marcarDbInicializada();
      });

      test('cuando se intenta generar otra sal, lanza StateError y no pisa la guardada', () async {
        await almacen.escribir(ClaveSegura.salDb, base64Encode(List<int>.filled(32, 3)));

        await expectLater(custodia.generarSal(), throwsA(isA<StateError>()));
        expect(await custodia.leerSal(), List<int>.filled(32, 3));
      });

      test('cuando primero se olvida, se puede volver a generar', () async {
        await custodia.olvidar();

        await expectLater(custodia.generarSal(), completes);
      });
    });
  });

  group('CustodiaClaveDb — marca de inicialización', () {
    test('dado un dispositivo nuevo, no está inicializado', () async {
      expect(await custodia.dbInicializada(), isFalse);
    });

    test('cuando se marca, queda inicializado', () async {
      await custodia.marcarDbInicializada();

      expect(await custodia.dbInicializada(), isTrue);
    });

    test('cuando la marca guardada no es la esperada, no cuenta como inicializado', () async {
      await almacen.escribir(ClaveSegura.dbInicializada, 'cualquier cosa');

      expect(await custodia.dbInicializada(), isFalse);
    });
  });

  group('CustodiaClaveDb.olvidar', () {
    test('cuando se olvida, borra la sal y la marca', () async {
      await custodia.generarSal();
      await custodia.marcarDbInicializada();

      await custodia.olvidar();

      expect(await custodia.leerSal(), isNull);
      expect(await custodia.dbInicializada(), isFalse);
      expect(almacen.contenido, isEmpty);
    });
  });

  group('CustodiaClaveDb — invariantes de seguridad', () {
    test('la custodia solo guarda la sal y la marca: nunca una clave', () async {
      await custodia.generarSal();
      await custodia.marcarDbInicializada();

      expect(
        almacen.contenido.keys,
        unorderedEquals(<ClaveSegura>[ClaveSegura.salDb, ClaveSegura.dbInicializada]),
      );
    });

    test('cuando el almacén seguro falla, la falla se propaga sin inventar una sal', () async {
      almacen.simularFalla = true;
      final falla = throwsA(isA<AlmacenSeguroException>());

      await expectLater(custodia.leerSal(), falla);
      await expectLater(custodia.generarSal(), falla);
      await expectLater(custodia.marcarDbInicializada(), falla);
      await expectLater(custodia.olvidar(), falla);
    });
  });

  group('SalCorruptaException', () {
    test('cuando se imprime, dice el motivo sin el valor leído', () {
      const falla = SalCorruptaException('no es base64');

      expect(falla.toString(), 'SalCorruptaException(no es base64)');
    });
  });
}
