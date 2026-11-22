// El cierre de la raíz (HU-AUTH-006, HU-SYNC-006): tirar un `ProviderScope` no cierra la base, así que
// al reiniciar la app la clave de la raíz vieja quedaba viva y la nueva abría una segunda conexión al
// mismo archivo. Se prueba con SQLCipher de verdad (el mismo mecanismo que en el teléfono): una base
// en memoria no se enteraría de si quedó abierta.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/arranque/cierre_de_la_raiz.dart';
import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

ClaveDb _clave() => ClaveDb(Uint8List.fromList(List<int>.filled(32, 7)));

void main() {
  late Directory directorio;
  late CierreDeLaRaiz cierre;
  final helpers = <DatabaseHelper>[];

  DatabaseHelper nuevoHelper() {
    final helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
    helpers.add(helper);
    return helper;
  }

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_cierre_raiz_test');
    cierre = CierreDeLaRaiz(logger: loggerMudo());
  });

  tearDown(() async {
    for (final helper in helpers) {
      await helper.cerrar();
    }
    helpers.clear();
    await directorio.delete(recursive: true);
  });

  test('dada una base abierta, al tirar la raíz se cierra y su clave se destruye', () async {
    final helper = cierre.adoptar(nuevoHelper());
    final clave = _clave();
    await helper.abrir(clave);
    expect(helper.abierta, isTrue, reason: 'sin el cierre la base seguiría abierta');
    expect(clave.destruida, isFalse);

    await cierre.alTirar();

    expect(helper.abierta, isFalse);
    expect(
      clave.destruida,
      isTrue,
      reason: 'la DEK en claro no puede sobrevivir al cierre de sesión',
    );
  });

  test('la raíz nueva abre el mismo archivo sin chocar con la vieja', () async {
    final viejo = cierre.adoptar(nuevoHelper());
    await viejo.abrir(_clave());
    await cierre.alTirar();

    final nuevo = cierre.adoptar(nuevoHelper());
    final db = await nuevo.abrir(_clave());

    expect(nuevo.abierta, isTrue);
    expect(viejo.abierta, isFalse);
    expect((await db.customSelect('SELECT 1 AS uno').getSingle()).read<int>('uno'), 1);
  });

  test('espera a los cierres anotados (el ciclo del motor) antes de cerrar la base', () async {
    final helper = cierre.adoptar(nuevoHelper());
    await helper.abrir(_clave());
    final cicloEnCurso = Completer<void>();
    cierre.registrar(cicloEnCurso.future);

    var terminado = false;
    final cierreDeLaBase = cierre.alTirar().then((_) => terminado = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(helper.abierta, isTrue, reason: 'el ciclo todavía usa la base: no se cierra debajo');
    expect(terminado, isFalse);

    cicloEnCurso.complete();
    await cierreDeLaBase;

    expect(helper.abierta, isFalse);
  });

  test('un cierre anotado que falla no frena el cierre de la base', () async {
    final helper = cierre.adoptar(nuevoHelper());
    await helper.abrir(_clave());
    cierre.registrar(Future<void>.error(StateError('el motor no cerró')));

    await cierre.alTirar();

    expect(helper.abierta, isFalse);
  });

  test('un cierre que se anota mientras se espera también se espera', () async {
    final helper = cierre.adoptar(nuevoHelper());
    await helper.abrir(_clave());
    final primero = Completer<void>();
    final segundo = Completer<void>();
    cierre.registrar(primero.future);

    final cierreDeLaBase = cierre.alTirar();
    await Future<void>.delayed(Duration.zero);
    cierre.registrar(segundo.future);
    primero.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(helper.abierta, isTrue);

    segundo.complete();
    await cierreDeLaBase;

    expect(helper.abierta, isFalse);
  });

  test('sin base adoptada (una pantalla suelta) no hace nada ni lanza', () async {
    await expectLater(cierre.alTirar(), completes);
  });

  test('tirar dos veces seguidas no vuelve a cerrar lo ya cerrado', () async {
    final helper = cierre.adoptar(nuevoHelper());
    await helper.abrir(_clave());

    await cierre.alTirar();
    await expectLater(cierre.alTirar(), completes);

    expect(helper.abierta, isFalse);
  });

  test(
    'una base que nunca se abrió (la raíz se tiró antes del login) se cierra sin error',
    () async {
      final helper = cierre.adoptar(nuevoHelper());

      await expectLater(cierre.alTirar(), completes);

      expect(helper.abierta, isFalse);
    },
  );
}
