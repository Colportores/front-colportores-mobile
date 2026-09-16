// Test de la custodia de la sal: Dart puro, con el almacén seguro en memoria.
import 'dart:convert';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:test/test.dart';

import '../../../helpers/logger_mudo.dart';

/// Almacén que falla al borrar una clave puntual y deja el resto en el almacén interno. Simula el
/// Keystore muriéndose a mitad de `olvidar()`, para ver con qué estado queda el dispositivo.
final class _AlmacenQueFallaAlBorrar implements AlmacenSeguro {
  _AlmacenQueFallaAlBorrar(this._interno, {required this.fallaEn});

  final AlmacenSeguroEnMemoria _interno;
  final ClaveSegura fallaEn;

  @override
  Future<String?> leer(ClaveSegura clave) => _interno.leer(clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) => _interno.escribir(clave, valor);

  @override
  Future<void> borrar(ClaveSegura clave) {
    if (clave == fallaEn) {
      throw AlmacenSeguroException(operacion: 'borrar', clave: clave);
    }
    return _interno.borrar(clave);
  }

  @override
  Future<void> borrarTodo() => _interno.borrarTodo();
}

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late CustodiaClaveDb custodia;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    custodia = CustodiaClaveDb(almacen, logger: loggerMudo());
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

    group('dado que la marca guardada no es la esperada', () {
      setUp(() async {
        await almacen.escribir(ClaveSegura.dbInicializada, 'cualquier cosa');
      });

      test('cuando se consulta, lanza MarcaInicializacionCorruptaException', () async {
        await expectLater(
          custodia.dbInicializada(),
          throwsA(isA<MarcaInicializacionCorruptaException>()),
        );
      });

      test(
        'cuando se intenta generar una sal, la guarda no se desactiva: lanza y no escribe',
        () async {
          await expectLater(
            custodia.generarSal(),
            throwsA(isA<MarcaInicializacionCorruptaException>()),
          );
          expect(almacen.contenido.containsKey(ClaveSegura.salDb), isFalse);
        },
      );

      test('cuando se olvida, se sale del estado corrupto sin leer la marca', () async {
        await custodia.olvidar();

        expect(await custodia.dbInicializada(), isFalse);
        await expectLater(custodia.generarSal(), completes);
      });
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

    group('dado que el almacén muere después del primer borrado', () {
      // Fija el orden marca → sal. Si fuera al revés, el estado parcial sería "sin sal + marca
      // puesta": leerSal() diría dispositivo nuevo y generarSal() lanzaría StateError siempre.
      late CustodiaClaveDb custodiaFragil;

      setUp(() async {
        await custodia.generarSal();
        await custodia.marcarDbInicializada();
        custodiaFragil = CustodiaClaveDb(
          _AlmacenQueFallaAlBorrar(almacen, fallaEn: ClaveSegura.salDb),
          logger: loggerMudo(),
        );
      });

      test('cuando se olvida, propaga la falla y la marca ya no está', () async {
        await expectLater(custodiaFragil.olvidar(), throwsA(isA<AlmacenSeguroException>()));

        expect(almacen.contenido.containsKey(ClaveSegura.dbInicializada), isFalse);
        expect(almacen.contenido.containsKey(ClaveSegura.salDb), isTrue);
      });

      test('cuando se olvida a medias, el dispositivo puede rehacerse con generarSal', () async {
        await expectLater(custodiaFragil.olvidar(), throwsA(isA<AlmacenSeguroException>()));

        expect(await custodia.dbInicializada(), isFalse);
        await expectLater(custodia.generarSal(), completes);
      });
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

  group('MarcaInicializacionCorruptaException', () {
    test('cuando se imprime, dice el motivo sin el valor leído', () {
      const falla = MarcaInicializacionCorruptaException('no es la marca esperada');

      expect(falla.toString(), 'MarcaInicializacionCorruptaException(no es la marca esperada)');
    });
  });
}
