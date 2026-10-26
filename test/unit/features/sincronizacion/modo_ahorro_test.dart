// El modo ahorro de datos (HU-SYNC-008): lo que el teléfono recuerda en el almacén seguro y el
// estado que se lo cuenta a la pantalla y al motor.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/sync/modo_ahorro_providers.dart';
import 'package:colportores_mobile/features/sincronizacion/data/repositories/modo_ahorro_repository_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

({ProviderContainer c, ModoAhorroRepositoryEnMemoria repo}) _armar({bool inicial = false}) {
  final repo = ModoAhorroRepositoryEnMemoria(activo: inicial);
  final c = ProviderContainer(
    overrides: [
      modoAhorroRepositoryProvider.overrideWithValue(repo),
      modoAhorroInicialProvider.overrideWithValue(inicial),
    ],
  );
  addTearDown(c.dispose);
  c.listen(modoAhorroProvider, (_, _) {});
  return (c: c, repo: repo);
}

void main() {
  group('ModoAhorroRepositoryImpl', () {
    late AlmacenSeguroEnMemoria almacen;
    late ModoAhorroRepositoryImpl repositorio;

    setUp(() {
      almacen = AlmacenSeguroEnMemoria();
      repositorio = ModoAhorroRepositoryImpl(almacen, logger: loggerMudo());
    });

    test('should be off when nothing was saved', () async {
      expect(await repositorio.leer(), isFalse);
    });

    test('should save "1" when on and remove the key when off', () async {
      await repositorio.guardar(activo: true);
      expect(almacen.contenido[ClaveSegura.modoAhorroDatos], '1');
      expect(await repositorio.leer(), isTrue);

      await repositorio.guardar(activo: false);
      expect(almacen.contenido.containsKey(ClaveSegura.modoAhorroDatos), isFalse);
      expect(await repositorio.leer(), isFalse);
    });

    test('should read as off a value that is not "1"', () async {
      await almacen.escribir(ClaveSegura.modoAhorroDatos, 'quizás');

      expect(await repositorio.leer(), isFalse);
    });
  });

  group('ModoAhorroNotifier', () {
    test('should start with the saved value', () {
      expect(_armar().c.read(modoAhorroProvider), isFalse);
      expect(_armar(inicial: true).c.read(modoAhorroProvider), isTrue);
    });

    test('should switch on and save', () async {
      final t = _armar();

      final ok = await t.c.read(modoAhorroProvider.notifier).cambiar(activo: true);

      expect(ok, isTrue);
      expect(t.c.read(modoAhorroProvider), isTrue);
      expect(t.repo.activo, isTrue);
    });

    test('should give the old value back and say it failed when saving fails', () async {
      final t = _armar()..repo.fallaAlGuardar = true;

      final ok = await t.c.read(modoAhorroProvider.notifier).cambiar(activo: true);

      expect(ok, isFalse);
      expect(t.c.read(modoAhorroProvider), isFalse);
      expect(t.repo.activo, isFalse);
    });

    test('should not save again what is already so', () async {
      final t = _armar(inicial: true);

      final ok = await t.c.read(modoAhorroProvider.notifier).cambiar(activo: true);

      expect(ok, isTrue);
      expect(t.repo.guardados, 0);
    });

    test('should apply changes in a row in the order they were asked', () async {
      final t = _armar();
      final notifier = t.c.read(modoAhorroProvider.notifier);

      final a = notifier.cambiar(activo: true);
      final b = notifier.cambiar(activo: false);
      final c = notifier.cambiar(activo: true);

      expect(await Future.wait([a, b, c]), [true, true, true]);
      expect(t.c.read(modoAhorroProvider), isTrue);
      expect(t.repo.activo, isTrue);
      expect(t.repo.guardados, 3);
    });

    test('should keep applying after a failed change', () async {
      final t = _armar();
      final notifier = t.c.read(modoAhorroProvider.notifier);
      t.repo.fallaAlGuardar = true;
      expect(await notifier.cambiar(activo: true), isFalse);

      t.repo.fallaAlGuardar = false;
      expect(await notifier.cambiar(activo: true), isTrue);

      expect(t.c.read(modoAhorroProvider), isTrue);
    });
  });
}
