// La preferencia «No volver a mostrar» del aviso de privacidad (#445, decisión de Cristian 23/10
// «Aviso privado»): una por cuenta, en el teléfono, para el alta de persona y las notas.
import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/configuracion/data/repositories/aviso_privacidad_repository_impl.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/aviso_privacidad_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

import '../../../helpers/logger_mudo.dart';

void main() {
  group('AvisoPrivacidadRepositoryImpl (sobre el almacén seguro)', () {
    late AlmacenSeguroEnMemoria almacen;
    late AvisoPrivacidadRepositoryImpl repo;

    setUp(() {
      almacen = AlmacenSeguroEnMemoria();
      repo = AvisoPrivacidadRepositoryImpl(almacen, logger: loggerMudo());
    });

    test('al principio nadie lo escondió: el aviso se ve', () async {
      expect(await repo.estaOculto('u-1'), isFalse);
    });

    test('esconderlo es por cuenta: otra cuenta del mismo teléfono lo sigue viendo', () async {
      await repo.ocultar('u-1');

      expect(await repo.estaOculto('u-1'), isTrue);
      expect(await repo.estaOculto('u-2'), isFalse);
    });

    test('esconderlo dos veces no duplica y volver a mostrarlo lo recupera', () async {
      await repo.ocultar('u-1');
      await repo.ocultar('u-1');
      expect(almacen.contenido[ClaveSegura.avisoPrivacidadOculto], '["u-1"]');

      await repo.mostrar('u-1');
      expect(await repo.estaOculto('u-1'), isFalse);
    });

    test('lo guardado son solo ids de cuenta, sin correos ni nombres', () async {
      await repo.ocultar('u-1');
      await repo.ocultar('u-2');

      expect(almacen.contenido[ClaveSegura.avisoPrivacidadOculto], '["u-1","u-2"]');
    });

    test(
      'cuando nadie lo tiene escondido borra la clave en vez de dejar una lista vacía',
      () async {
        await repo.ocultar('u-1');

        await repo.mostrar('u-1');

        expect(almacen.contenido.containsKey(ClaveSegura.avisoPrivacidadOculto), isFalse);
      },
    );

    test('mostrar a quien nunca lo escondió no escribe nada', () async {
      await repo.mostrar('u-1');

      expect(almacen.contenido, isEmpty);
    });

    test('un valor ilegible cuenta como «nadie lo escondió» y se arregla al guardar', () async {
      await almacen.escribir(ClaveSegura.avisoPrivacidadOculto, '{no es json');
      expect(await repo.estaOculto('u-1'), isFalse);

      await repo.ocultar('u-1');

      expect(almacen.contenido[ClaveSegura.avisoPrivacidadOculto], '["u-1"]');
    });

    test('un JSON que no es una lista, o con basura adentro, no rompe nada', () async {
      await almacen.escribir(ClaveSegura.avisoPrivacidadOculto, '{"u-1":true}');
      expect(await repo.estaOculto('u-1'), isFalse);

      await almacen.escribir(ClaveSegura.avisoPrivacidadOculto, '[1, null, "", "u-1"]');
      expect(await repo.estaOculto('u-1'), isTrue);
      expect(await repo.estaOculto('u-2'), isFalse);
    });

    test('si el almacén no se deja leer, el aviso se ve (ante la duda, se muestra)', () async {
      await repo.ocultar('u-1');
      almacen.simularFalla = true;

      expect(await repo.estaOculto('u-1'), isFalse);
    });

    test('si el almacén no deja escribir, el error sale y no queda nada a medias', () async {
      almacen.simularFalla = true;

      await expectLater(repo.ocultar('u-1'), throwsA(isA<AlmacenSeguroException>()));

      almacen.simularFalla = false;
      expect(await repo.estaOculto('u-1'), isFalse);
    });

    test(
      'después de una falla, la siguiente operación funciona (la cola no queda trabada)',
      () async {
        almacen.simularFalla = true;
        await expectLater(repo.ocultar('u-1'), throwsA(isA<AlmacenSeguroException>()));
        almacen.simularFalla = false;

        await repo.ocultar('u-1');

        expect(await repo.estaOculto('u-1'), isTrue);
      },
    );

    test('dos cambios seguidos de cuentas distintas no se pisan', () async {
      final a = repo.ocultar('u-1');
      final b = repo.ocultar('u-2');
      await Future.wait([a, b]);

      expect(await repo.estaOculto('u-1'), isTrue);
      expect(await repo.estaOculto('u-2'), isTrue);
    });

    test('esconder y volver a mostrar sin esperar deja la última palabra', () async {
      final a = repo.ocultar('u-1');
      final b = repo.mostrar('u-1');
      await Future.wait([a, b]);

      expect(await repo.estaOculto('u-1'), isFalse);
    });
  });

  group('avisoPrivacidadOcultoProvider', () {
    late AvisoPrivacidadEnMemoria repo;
    late ProviderContainer container;

    setUp(() {
      repo = AvisoPrivacidadEnMemoria();
      container = ProviderContainer(
        overrides: [avisoPrivacidadRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
    });

    Future<bool> leer(String cuenta) =>
        container.read(avisoPrivacidadOcultoProvider(cuenta).future);

    test('empieza con el aviso a la vista', () async {
      expect(await leer('u-1'), isFalse);
    });

    test('ocultar guarda y actualiza el estado', () async {
      await leer('u-1');

      final guardado = await container
          .read(avisoPrivacidadOcultoProvider('u-1').notifier)
          .ocultar();

      expect(guardado, isTrue);
      expect(container.read(avisoPrivacidadOcultoProvider('u-1')).value, isTrue);
      expect(repo.ocultas, {'u-1'});
    });

    test('mostrar lo recupera', () async {
      repo = AvisoPrivacidadEnMemoria(['u-1']);
      container.dispose();
      container = ProviderContainer(
        overrides: [avisoPrivacidadRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      expect(await leer('u-1'), isTrue);

      final guardado = await container
          .read(avisoPrivacidadOcultoProvider('u-1').notifier)
          .mostrar();

      expect(guardado, isTrue);
      expect(container.read(avisoPrivacidadOcultoProvider('u-1')).value, isFalse);
    });

    test('si no se puede guardar devuelve false y el aviso sigue a la vista', () async {
      await leer('u-1');
      repo.fallaAlEscribir = true;

      final guardado = await container
          .read(avisoPrivacidadOcultoProvider('u-1').notifier)
          .ocultar();

      expect(guardado, isFalse);
      expect(container.read(avisoPrivacidadOcultoProvider('u-1')).value, isFalse);
      expect(repo.ocultas, isEmpty);
    });

    test('después de una falla se puede volver a intentar', () async {
      await leer('u-1');
      repo.fallaAlEscribir = true;
      final notificador = container.read(avisoPrivacidadOcultoProvider('u-1').notifier);
      expect(await notificador.ocultar(), isFalse);

      repo.fallaAlEscribir = false;

      expect(await notificador.ocultar(), isTrue);
      expect(repo.ocultas, {'u-1'});
    });

    test('dos toques seguidos guardan una sola vez: el segundo se descarta', () async {
      await leer('u-1');
      final compuerta = repo.compuerta = Completer<void>();
      final notificador = container.read(avisoPrivacidadOcultoProvider('u-1').notifier);

      final primero = notificador.ocultar();
      final segundo = await notificador.ocultar();
      compuerta.complete();

      expect(segundo, isFalse);
      expect(await primero, isTrue);
      expect(repo.escrituras, 1);
    });

    test('si no se puede leer, el aviso se ve', () async {
      repo.fallaAlLeer = true;

      expect(await leer('u-1'), isFalse);
    });

    test('cada cuenta tiene su propio estado', () async {
      await leer('u-1');
      await container.read(avisoPrivacidadOcultoProvider('u-1').notifier).ocultar();

      expect(await leer('u-2'), isFalse);
    });
  });
}
