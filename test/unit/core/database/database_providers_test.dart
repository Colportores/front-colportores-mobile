// Cableado de la DB local: el helper no trae implementación por defecto y dbLocalProvider sigue
// el ciclo abrir/cerrar.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

ClaveDb _clave() => ClaveDb(Uint8List.fromList(List<int>.filled(32, 5)));

void main() {
  group('databaseHelperProvider', () {
    test('dado que nadie lo inyectó, falla en vez de inventar un directorio', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(databaseHelperProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    });
  });

  group('dbLocalProvider', () {
    late Directory directorio;
    late DatabaseHelper helper;
    late ProviderContainer container;

    setUp(() async {
      directorio = await Directory.systemTemp.createTemp('colportores_db_providers_test');
      helper = DatabaseHelper(
        directorio: () async => directorio,
        directorioTemporal: () async => directorio,
        logger: loggerMudo(),
      );
      container = ProviderContainer(overrides: [databaseHelperProvider.overrideWithValue(helper)]);
    });

    tearDown(() async {
      container.dispose();
      await helper.cerrar();
      await directorio.delete(recursive: true);
    });

    test('dado que arranca la app, la DB es null', () {
      expect(container.read(dbLocalProvider), isNull);
    });

    test('cuando abre, publica la DB y el helper queda abierto', () async {
      final db = await container.read(dbLocalProvider.notifier).abrir(_clave());

      expect(container.read(dbLocalProvider), same(db));
      expect(helper.abierta, isTrue);
      expect(helper.db, same(db));
    });

    test('cuando cierra, vuelve a null y la clave queda destruida', () async {
      final clave = _clave();
      await container.read(dbLocalProvider.notifier).abrir(clave);

      await container.read(dbLocalProvider.notifier).cerrar();

      expect(container.read(dbLocalProvider), isNull);
      expect(helper.abierta, isFalse);
      expect(clave.destruida, isTrue);
    });

    test('dado una apertura en vuelo, cuando cierra, la DB termina cerrada y en null', () async {
      final clave = _clave();
      final notifier = container.read(dbLocalProvider.notifier);

      // Sin esperar la apertura: es el logout que llega mientras el login todavía abre la DB.
      final apertura = notifier.abrir(clave);
      final cierre = notifier.cerrar();

      // Orden que se cubre: el cierre espera su turno en el helper, la continuación de abrir()
      // publica la DB recién abierta, el helper la cierra y el finally de cerrar() deja null.
      await apertura;
      await cierre;

      expect(container.read(dbLocalProvider), isNull);
      expect(helper.abierta, isFalse, reason: 'el logout no puede dejar la DB abierta');
      expect(clave.destruida, isTrue);
    });

    test('dado que abrir falla, la DB sigue en null y el error se propaga', () async {
      await container.read(dbLocalProvider.notifier).abrir(_clave());
      await container.read(dbLocalProvider.notifier).cerrar();
      final otra = ClaveDb(Uint8List.fromList(List<int>.filled(32, 6)));

      await expectLater(
        container.read(dbLocalProvider.notifier).abrir(otra),
        throwsA(isA<ClaveDbIncorrectaException>()),
      );

      expect(container.read(dbLocalProvider), isNull);
    });

    test('dado que nunca se abrió, cerrar no toca el helper', () async {
      final sinHelper = ProviderContainer();
      addTearDown(sinHelper.dispose);

      await expectLater(sinHelper.read(dbLocalProvider.notifier).cerrar(), completes);

      expect(sinHelper.read(dbLocalProvider), isNull);
    });

    test('dado que nunca se abrió, cerrar igual cuenta el pedido (HU-AUTH-009)', () async {
      final notifier = container.read(dbLocalProvider.notifier);
      expect(notifier.cierresPedidos, 0);

      final cierre = notifier.cerrar();

      // Contado antes del primer await: el flujo de inicialización lo ve sin esperar nada.
      expect(notifier.cierresPedidos, 1);
      await cierre;
      await notifier.cerrar();
      expect(notifier.cierresPedidos, 2);
    });
  });
}
