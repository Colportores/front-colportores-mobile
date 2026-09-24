// Test de la custodia de la DEK (ADR-006): almacén seguro en memoria, envoltorio en un directorio
// temporal, Argon2id de juguete y el cifrado de la DEK real (libsodium).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../helpers/logger_mudo.dart';
import '../../../helpers/proveedor_clave_db_falso.dart';

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

/// Almacén que falla en la escritura número [fallaEnEscritura] (contando desde 1) y deja escrito
/// lo anterior: un Keystore que se corta a mitad de la reconstrucción.
final class _AlmacenQueFallaAlEscribir implements AlmacenSeguro {
  _AlmacenQueFallaAlEscribir(this._interno, {required this.fallaEnEscritura});

  final AlmacenSeguroEnMemoria _interno;
  final int fallaEnEscritura;
  int _escrituras = 0;

  @override
  Future<String?> leer(ClaveSegura clave) => _interno.leer(clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) {
    if (++_escrituras == fallaEnEscritura) {
      throw AlmacenSeguroException(operacion: 'escribir', clave: clave);
    }
    return _interno.escribir(clave, valor);
  }

  @override
  Future<void> borrar(ClaveSegura clave) => _interno.borrar(clave);

  @override
  Future<void> borrarTodo() => _interno.borrarTodo();
}

const _parametros = ParametrosArgon2id(memoriaBytes: 64 * 1024, iteraciones: 1, paralelismo: 1);

void main() {
  late Directory dir;
  late AlmacenSeguroEnMemoria almacen;
  late ArchivoEnvoltorioDek archivo;
  late ProveedorClaveDbFalso proveedor;
  late CustodiaClaveDb custodia;

  CustodiaClaveDb custodiaCon(AlmacenSeguro almacen, {ParametrosArgon2id? parametros}) =>
      CustodiaClaveDb(
        almacen,
        archivo,
        proveedor,
        CriptoSodium(),
        parametros: parametros ?? _parametros,
        logger: loggerMudo(),
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('custodia_');
    almacen = AlmacenSeguroEnMemoria();
    archivo = ArchivoEnvoltorioDek(directorio: () async => dir);
    proveedor = ProveedorClaveDbFalso();
    custodia = custodiaCon(almacen);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<String> contenidoDelEnvoltorio() =>
      File(p.join(dir.path, ArchivoEnvoltorioDek.nombreArchivoPorDefecto)).readAsString();

  group('CustodiaClaveDb — DEK en el almacén seguro', () {
    test('dado un dispositivo nuevo, no hay DEK', () async {
      expect(await custodia.leerDek(), isNull);
    });

    test('cuando genera una DEK, tiene 32 bytes, es distinta cada vez y no la guarda', () async {
      final a = custodia.generarDek();
      final b = custodia.generarDek();

      expect(a.bytes, hasLength(32));
      expect(a.bytes, isNot(b.bytes));
      expect(almacen.contenido, isEmpty);
    });

    test('dada una DEK guardada, cuando se lee, vuelve la misma y se puede destruir', () async {
      final dek = custodia.generarDek();
      await custodia.guardarDek(dek);

      final leida = await custodia.leerDek();

      expect(leida!.bytes, dek.bytes);
      expect(almacen.contenido[ClaveSegura.dekDb], base64Encode(dek.bytes));
      expect(leida.destruir, returnsNormally);
    });

    test(
      'cuando guarda otra DEK sin marca puesta, reemplaza la anterior (reintento desde cero)',
      () async {
        await custodia.guardarDek(custodia.generarDek());
        final segunda = custodia.generarDek();

        await custodia.guardarDek(segunda);

        expect((await custodia.leerDek())!.bytes, segunda.bytes);
      },
    );

    group('dado un dispositivo ya inicializado', () {
      late ClaveDb original;

      setUp(() async {
        original = custodia.generarDek();
        await custodia.guardarDek(original);
        await custodia.marcarDbInicializada();
      });

      test('cuando se intenta guardar otra DEK, lanza StateError y no pisa la de la DB', () async {
        await expectLater(custodia.guardarDek(custodia.generarDek()), throwsA(isA<StateError>()));
        expect((await custodia.leerDek())!.bytes, original.bytes);
      });

      test('cuando se olvida primero, la puede reemplazar', () async {
        await custodia.olvidar();

        await expectLater(custodia.guardarDek(custodia.generarDek()), completes);
      });
    });

    group('dado que lo guardado no es una DEK', () {
      test('cuando no es base64, lanza DekCorruptaException sin el valor', () async {
        await almacen.escribir(ClaveSegura.dekDb, 'no es base64!!');

        await expectLater(
          custodia.leerDek(),
          throwsA(
            isA<DekCorruptaException>().having(
              (e) => e.toString(),
              'toString',
              isNot(contains('!!')),
            ),
          ),
        );
      });

      test('cuando no tiene 32 bytes, lanza DekCorruptaException', () async {
        await almacen.escribir(ClaveSegura.dekDb, base64Encode(List<int>.filled(16, 0)));

        await expectLater(custodia.leerDek(), throwsA(isA<DekCorruptaException>()));
      });
    });
  });

  group('CustodiaClaveDb — envoltorio por contraseña', () {
    test(
      'dado un equipo sin envoltorio, no lo hay y desenvolver lanza SinEnvoltorioException',
      () async {
        expect(await custodia.hayEnvoltorioPorPassword(), isFalse);
        await expectLater(
          custodia.desenvolverConPassword('secreto123'),
          throwsA(isA<SinEnvoltorioException>()),
        );
      },
    );

    test('cuando envuelve con la contraseña, la misma contraseña la desenvuelve', () async {
      final dek = custodia.generarDek();

      await custodia.envolverConPassword(dek, 'secreto123');
      final recuperada = await custodia.desenvolverConPassword('secreto123');

      expect(await custodia.hayEnvoltorioPorPassword(), isTrue);
      expect(recuperada.bytes, dek.bytes);
      expect(dek.destruida, isFalse, reason: 'envolver no toca la DEK de quien la pasó');
    });

    test('dada otra contraseña, lanza EnvoltorioNoAbreException', () async {
      await custodia.envolverConPassword(custodia.generarDek(), 'secreto123');

      await expectLater(
        custodia.desenvolverConPassword('otra-cosa'),
        throwsA(isA<EnvoltorioNoAbreException>()),
      );
    });

    test('el archivo lleva la cabecera con los parámetros y nunca la DEK en claro', () async {
      final dek = custodia.generarDek();

      await custodia.envolverConPassword(dek, 'secreto123');
      final texto = await contenidoDelEnvoltorio();
      final envoltorio = EnvoltorioDek.decodificar(texto);

      expect(envoltorio.parametros, _parametros);
      expect(envoltorio.algoritmo, EnvoltorioDek.algoritmoActual);
      expect(envoltorio.sal, hasLength(EnvoltorioDek.bytesSal));
      expect(texto, isNot(contains(base64Encode(dek.bytes))));
      expect(texto, isNot(contains('secreto123')));
    });

    test('cada envoltorio usa una sal nueva', () async {
      final dek = custodia.generarDek();

      await custodia.envolverConPassword(dek, 'secreto123');
      final primera = EnvoltorioDek.decodificar(await contenidoDelEnvoltorio()).sal;
      await custodia.envolverConPassword(dek, 'secreto123');
      final segunda = EnvoltorioDek.decodificar(await contenidoDelEnvoltorio()).sal;

      expect(primera, isNot(segunda));
    });

    test('la clave derivada se destruye al terminar, salga bien o mal', () async {
      await custodia.envolverConPassword(custodia.generarDek(), 'secreto123');
      await expectLater(custodia.desenvolverConPassword('otra'), throwsA(anything));

      expect(proveedor.entregadas, hasLength(2));
      expect(proveedor.entregadas.every((c) => c.destruida), isTrue);
    });

    test(
      'dado un envoltorio armado con otros parámetros, desenvuelve con los de su cabecera',
      () async {
        const viejos = ParametrosArgon2id(memoriaBytes: 32 * 1024, iteraciones: 2, paralelismo: 1);
        final dek = custodia.generarDek();
        await custodiaCon(almacen, parametros: viejos).envolverConPassword(dek, 'secreto123');

        final recuperada = await custodia.desenvolverConPassword('secreto123');

        expect(recuperada.bytes, dek.bytes);
        expect(proveedor.parametrosPedidos.last, viejos);
      },
    );

    test(
      'dado un envoltorio de un algoritmo desconocido, lanza EnvoltorioCorruptoException',
      () async {
        await custodia.envolverConPassword(custodia.generarDek(), 'secreto123');
        final json = jsonDecode(await contenidoDelEnvoltorio()) as Map<String, Object?>;
        json['alg'] = 'rot13';
        await File(
          p.join(dir.path, ArchivoEnvoltorioDek.nombreArchivoPorDefecto),
        ).writeAsString(jsonEncode(json));

        await expectLater(
          custodia.desenvolverConPassword('secreto123'),
          throwsA(isA<EnvoltorioCorruptoException>()),
        );
      },
    );

    test('dado que la derivación falla, la falla se propaga y no se escribe nada', () async {
      proveedor.falla = const CriptoException('derivar', 'sin memoria');

      await expectLater(
        custodia.envolverConPassword(custodia.generarDek(), 'secreto123'),
        throwsA(isA<CriptoException>()),
      );
      expect(await custodia.hayEnvoltorioPorPassword(), isFalse);
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
        'cuando se intenta guardar una DEK, la guarda no se desactiva: lanza y no escribe',
        () async {
          await expectLater(
            custodia.guardarDek(custodia.generarDek()),
            throwsA(isA<MarcaInicializacionCorruptaException>()),
          );
          expect(almacen.contenido.containsKey(ClaveSegura.dekDb), isFalse);
        },
      );

      test('cuando se olvida, se sale del estado corrupto sin leer la marca', () async {
        await custodia.olvidar();

        expect(await custodia.dbInicializada(), isFalse);
        await expectLater(custodia.guardarDek(custodia.generarDek()), completes);
      });
    });
  });

  test('cuando se registra el consentimiento de S10, queda en el almacén', () async {
    await custodia.registrarConsentimientoAlmacenSoftware();

    expect(almacen.contenido[ClaveSegura.consentimientoAlmacenSoftware], 'true');
  });

  group('CustodiaClaveDb.reconstruirAlmacen (recuperación guiada)', () {
    test('conserva el consentimiento de S10 (#81)', () async {
      final dek = custodia.generarDek();
      await custodia.registrarConsentimientoAlmacenSoftware();

      await custodia.reconstruirAlmacen(dek);

      expect(almacen.contenido[ClaveSegura.consentimientoAlmacenSoftware], 'true');
    });

    for (final (escritura, queda) in [(1, 'nada'), (2, 'la marca sin DEK')]) {
      test('dado que el Keystore falla en la escritura $escritura, queda $queda: nunca "DEK sin '
          'marca", que se tomaría por una inicialización cortada (#81)', () async {
        final fragil = custodiaCon(
          _AlmacenQueFallaAlEscribir(almacen, fallaEnEscritura: escritura),
        );

        await expectLater(
          fragil.reconstruirAlmacen(custodia.generarDek()),
          throwsA(isA<AlmacenSeguroException>()),
        );

        expect(almacen.contenido.containsKey(ClaveSegura.dekDb), isFalse);
        expect(almacen.contenido.containsKey(ClaveSegura.dbInicializada), escritura == 2);
      });
    }

    test('limpia el almacén y lo reescribe con la DEK y la marca; el envoltorio queda', () async {
      final dek = custodia.generarDek();
      await custodia.envolverConPassword(dek, 'secreto123');
      await almacen.escribir(ClaveSegura.dekDb, 'basura');

      await custodia.reconstruirAlmacen(dek);

      expect(
        almacen.contenido.keys,
        unorderedEquals(<ClaveSegura>[ClaveSegura.dekDb, ClaveSegura.dbInicializada]),
      );
      expect((await custodia.leerDek())!.bytes, dek.bytes);
      expect(await custodia.dbInicializada(), isTrue);
      expect(await custodia.hayEnvoltorioPorPassword(), isTrue);
      expect(dek.destruida, isFalse);
    });
  });

  group('CustodiaClaveDb.olvidar', () {
    test('cuando se olvida, borra la marca, la DEK, el consentimiento y el envoltorio', () async {
      final dek = custodia.generarDek();
      await custodia.guardarDek(dek);
      await custodia.envolverConPassword(dek, 'secreto123');
      await custodia.registrarConsentimientoAlmacenSoftware();
      await custodia.marcarDbInicializada();

      await custodia.olvidar();

      expect(await custodia.leerDek(), isNull);
      expect(await custodia.dbInicializada(), isFalse);
      expect(await custodia.hayEnvoltorioPorPassword(), isFalse);
      expect(almacen.contenido, isEmpty);
    });

    test('dado un Keystore roto, borra igual el envoltorio y relanza la falla (#81)', () async {
      await custodia.envolverConPassword(custodia.generarDek(), 'secreto123');
      almacen.simularFalla = true;

      await expectLater(custodia.olvidar(), throwsA(isA<AlmacenSeguroException>()));

      expect(await custodia.hayEnvoltorioPorPassword(), isFalse);
    });

    group('dado que el almacén muere después del primer borrado', () {
      // Fija el orden marca → DEK. Si fuera al revés, el estado parcial sería "sin DEK + marca
      // puesta", y guardarDek() lanzaría StateError siempre.
      late CustodiaClaveDb custodiaFragil;

      setUp(() async {
        await custodia.guardarDek(custodia.generarDek());
        await custodia.marcarDbInicializada();
        custodiaFragil = custodiaCon(_AlmacenQueFallaAlBorrar(almacen, fallaEn: ClaveSegura.dekDb));
      });

      test('cuando se olvida, propaga la falla y la marca ya no está', () async {
        await expectLater(custodiaFragil.olvidar(), throwsA(isA<AlmacenSeguroException>()));

        expect(almacen.contenido.containsKey(ClaveSegura.dbInicializada), isFalse);
        expect(almacen.contenido.containsKey(ClaveSegura.dekDb), isTrue);
      });

      test('cuando se olvida a medias, el dispositivo puede rehacerse', () async {
        await expectLater(custodiaFragil.olvidar(), throwsA(isA<AlmacenSeguroException>()));

        expect(await custodia.dbInicializada(), isFalse);
        await expectLater(custodia.guardarDek(custodia.generarDek()), completes);
      });
    });
  });

  group('CustodiaClaveDb — invariantes de seguridad', () {
    test(
      'el almacén solo guarda la DEK y la marca: nunca la contraseña ni la clave derivada',
      () async {
        final dek = custodia.generarDek();
        await custodia.guardarDek(dek);
        await custodia.envolverConPassword(dek, 'secreto123');
        await custodia.marcarDbInicializada();

        expect(
          almacen.contenido.keys,
          unorderedEquals(<ClaveSegura>[ClaveSegura.dekDb, ClaveSegura.dbInicializada]),
        );
        expect(almacen.contenido.values, isNot(contains(contains('secreto123'))));
      },
    );

    test('cuando el almacén seguro falla, la falla se propaga sin inventar una DEK', () async {
      almacen.simularFalla = true;
      final falla = throwsA(isA<AlmacenSeguroException>());

      await expectLater(custodia.leerDek(), falla);
      await expectLater(custodia.guardarDek(custodia.generarDek()), falla);
      await expectLater(custodia.marcarDbInicializada(), falla);
      await expectLater(custodia.reconstruirAlmacen(custodia.generarDek()), falla);
      await expectLater(custodia.olvidar(), falla);
    });
  });

  test('las excepciones de la custodia dicen el motivo sin el valor leído', () {
    expect(
      const DekCorruptaException('no es base64').toString(),
      'DekCorruptaException(no es base64)',
    );
    expect(
      const MarcaInicializacionCorruptaException('x').toString(),
      'MarcaInicializacionCorruptaException(x)',
    );
    expect(const SinEnvoltorioException().toString(), 'SinEnvoltorioException()');
  });

  test('una DEK leída del almacén no comparte buffer con otra lectura', () async {
    await custodia.guardarDek(ClaveDb(Uint8List.fromList(List<int>.filled(32, 9))));

    final a = await custodia.leerDek();
    final b = await custodia.leerDek();
    a!.destruir();

    expect(b!.bytes, List<int>.filled(32, 9), reason: 'destruir una no rompe la otra');
  });
}
