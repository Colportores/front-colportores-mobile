// Test del helper contra SQLCipher de verdad: el binario que baja `package:sqlite3` (hooks) para
// Linux es el mismo mecanismo que en Android/iOS, así que lo que se verifica acá es el cifrado
// real, no un fake. Necesita flutter_test porque drift_flutter importa dart:ui.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;

import '../../../helpers/logger_mudo.dart';

/// Texto que se escribe en la DB y después se busca en el archivo crudo: si aparece, no hay cifrado.
const _marcador = 'TEXTO_PLANO_QUE_NO_PUEDE_APARECER_EN_DISCO';

ClaveDb _clave(int relleno) => ClaveDb(Uint8List.fromList(List<int>.filled(32, relleno)));

void main() {
  late Directory directorio;
  late DatabaseHelper helper;

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_db_test');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
  });

  tearDown(() async {
    await helper.cerrar();
    await directorio.delete(recursive: true);
  });

  Future<void> escribirMarcador(AppDatabase db) async {
    await db.customStatement('CREATE TABLE IF NOT EXISTS prueba (valor TEXT NOT NULL)');
    await db.customStatement("INSERT INTO prueba (valor) VALUES ('$_marcador')");
  }

  Future<String?> leerMarcador(AppDatabase db) async {
    final filas = await db.customSelect('SELECT valor FROM prueba').get();
    return filas.isEmpty ? null : filas.single.read<String>('valor');
  }

  group('DatabaseHelper.abrir', () {
    group('dado un dispositivo nuevo (sin archivo)', () {
      test('cuando abre, crea el archivo cifrado y queda abierta', () async {
        expect(await helper.existe(), isFalse);

        final db = await helper.abrir(_clave(1));

        expect(helper.abierta, isTrue);
        expect(helper.db, same(db));
        expect(await helper.existe(), isTrue);
      });

      test('cuando abre, el esquema queda en la versión declarada', () async {
        final db = await helper.abrir(_clave(1));

        final fila = await db.customSelect('PRAGMA user_version').getSingle();
        expect(fila.read<int>('user_version'), db.schemaVersion);
      });

      test('cuando abre, el binario es SQLCipher de verdad', () async {
        final db = await helper.abrir(_clave(1));

        final fila = await db.customSelect('PRAGMA cipher_version').getSingle();
        expect(fila.read<String>('cipher_version'), contains('4.'));
      });
    });

    group('dado que ya está abierta', () {
      setUp(() => helper.abrir(_clave(1)));

      test('cuando se intenta abrir de nuevo, lanza StateError sin tocar la abierta', () async {
        final clave = _clave(2);

        await expectLater(helper.abrir(clave), throwsA(isA<StateError>()));

        expect(helper.abierta, isTrue);
        expect(clave.destruida, isFalse, reason: 'no llegó a tomar la clave');
      });
    });

    test('dado que la clave ya fue destruida, cuando abre, lanza StateError', () async {
      final clave = _clave(1)..destruir();

      await expectLater(helper.abrir(clave), throwsA(isA<StateError>()));
      expect(helper.abierta, isFalse);
    });
  });

  group('DatabaseHelper — cifrado real', () {
    late File archivo;

    setUp(() async {
      final db = await helper.abrir(_clave(7));
      await escribirMarcador(db);
      await helper.cerrar();
      archivo = await helper.archivo();
    });

    test('cuando reabre con la misma clave, lee lo escrito', () async {
      final db = await helper.abrir(_clave(7));

      expect(await leerMarcador(db), _marcador);
    });

    test('cuando abre con otra clave, lanza ClaveDbIncorrectaException y queda cerrada', () async {
      final otra = _clave(8);

      await expectLater(helper.abrir(otra), throwsA(isA<ClaveDbIncorrectaException>()));

      expect(helper.abierta, isFalse);
      expect(() => helper.db, throwsStateError);
      expect(otra.destruida, isTrue, reason: 'la clave no sobrevive a un intento fallido');
      expect(await archivo.exists(), isTrue, reason: 'el archivo no se toca');
    });

    test('cuando abre con otra clave, la DB original sigue abriendo después', () async {
      await expectLater(helper.abrir(_clave(8)), throwsA(isA<ClaveDbIncorrectaException>()));

      final db = await helper.abrir(_clave(7));

      expect(await leerMarcador(db), _marcador);
    });

    test('cuando se abre sin clave (SQLite crudo), el archivo no es una base de datos', () {
      final crudo = sqlite3.open(archivo.path);
      addTearDown(crudo.close);

      expect(
        () => crudo.select('SELECT count(*) FROM sqlite_master'),
        throwsA(isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 26)),
      );
    });

    test('el archivo en disco no contiene el texto escrito', () async {
      final bytes = await archivo.readAsBytes();

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes), isNot(contains(_marcador)));
      expect(
        String.fromCharCodes(bytes.sublist(0, 15)),
        isNot('SQLite format 3'),
        reason: 'la cabecera de SQLite tampoco está en claro',
      );
    });
  });

  group('DatabaseHelper.cerrar', () {
    test('cuando cierra, destruye la clave y la DB deja de estar disponible', () async {
      final clave = _clave(1);
      await helper.abrir(clave);

      await helper.cerrar();

      expect(helper.abierta, isFalse);
      expect(clave.destruida, isTrue);
      expect(() => helper.db, throwsStateError);
    });

    test('cuando no hay nada abierto, no hace nada', () async {
      await expectLater(helper.cerrar(), completes);
      await expectLater(helper.cerrar(), completes);
    });

    test('cuando cierra, se puede volver a abrir con la misma clave re-derivada', () async {
      final db1 = await helper.abrir(_clave(3));
      await escribirMarcador(db1);
      await helper.cerrar();

      final db2 = await helper.abrir(_clave(3));

      expect(await leerMarcador(db2), _marcador);
    });
  });

  group('DatabaseHelper.borrar', () {
    test('dado que no existe el archivo, cuando borra, no hace nada', () async {
      await expectLater(helper.borrar(), completes);
      expect(await helper.existe(), isFalse);
    });

    test('dado que la DB está cerrada, cuando borra, elimina el archivo y sus anexos', () async {
      await helper.abrir(_clave(1));
      await helper.cerrar();
      final archivo = await helper.archivo();
      await File('${archivo.path}-journal').writeAsString('resto');
      await File('${archivo.path}-wal').writeAsString('resto');
      await File('${archivo.path}-shm').writeAsString('resto');

      await helper.borrar();

      expect(await helper.existe(), isFalse);
      expect(directorio.listSync(), isEmpty);
    });

    test('dado que la DB está abierta, cuando borra, lanza StateError y no toca nada', () async {
      await helper.abrir(_clave(1));

      await expectLater(helper.borrar(), throwsA(isA<StateError>()));

      expect(await helper.existe(), isTrue);
      expect(helper.abierta, isTrue);
    });

    test('después de borrar, abrir con cualquier clave crea una DB nueva vacía', () async {
      final db1 = await helper.abrir(_clave(1));
      await escribirMarcador(db1);
      await helper.cerrar();
      await helper.borrar();

      final db2 = await helper.abrir(_clave(9));

      expect(await helper.existe(), isTrue);
      expect(
        () => db2.customSelect('SELECT valor FROM prueba').get(),
        throwsA(anything),
        reason: 'la tabla de la DB anterior ya no existe',
      );
    });
  });

  group('DatabaseHelper — fallas de I/O', () {
    test('dado que la ruta no se puede crear, cuando abre, lanza DbLocalException', () async {
      // Un archivo donde debería ir el directorio: ni Drift ni SQLite pueden crear nada adentro.
      final bloqueo = File('${directorio.path}/bloqueo')..writeAsStringSync('no soy un directorio');
      final roto = DatabaseHelper(
        directorio: () async => Directory(bloqueo.path),
        directorioTemporal: () async => directorio,
        logger: loggerMudo(),
      );
      final clave = _clave(1);

      await expectLater(roto.abrir(clave), throwsA(isA<DbLocalException>()));

      expect(roto.abierta, isFalse);
      expect(clave.destruida, isTrue);
    });

    test('dado que resolver el directorio falla, cuando abre, lanza DbLocalException', () async {
      final roto = DatabaseHelper(
        directorio: () async => throw const FileSystemException('sin path_provider'),
        directorioTemporal: () async => directorio,
        logger: loggerMudo(),
      );
      final clave = _clave(1);

      await expectLater(
        roto.abrir(clave),
        throwsA(isA<DbLocalException>().having((e) => e.operacion, 'operacion', 'abrir')),
      );

      expect(roto.abierta, isFalse);
      expect(clave.destruida, isTrue);
    });
  });

  group('excepciones', () {
    test('cuando se imprimen, no llevan clave ni ruta', () {
      expect(
        const ClaveDbIncorrectaException().toString(),
        'ClaveDbIncorrectaException(file is not a database)',
      );
      expect(
        const DbLocalException(operacion: 'abrir', causa: 'detalle').toString(),
        'DbLocalException(abrir)',
      );
    });
  });
}
