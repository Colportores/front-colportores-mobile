// El correo de la última cuenta vive en el almacén seguro, solo él, y las operaciones salen en el
// orden en que se piden (decisión de Cristian, 01/10).
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Almacén donde escribir tarda, para probar el orden.
final class _AlmacenLento implements AlmacenSeguro {
  final AlmacenSeguroEnMemoria _real = AlmacenSeguroEnMemoria();

  @override
  Future<String?> leer(ClaveSegura clave) => _real.leer(clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _real.escribir(clave, valor);
  }

  @override
  Future<void> borrar(ClaveSegura clave) => _real.borrar(clave);

  @override
  Future<void> borrarTodo() => _real.borrarTodo();
}

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late UltimoCorreoRepositoryImpl repo;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = UltimoCorreoRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin nada guardado, no hay correo', () async {
    expect(await repo.leer(), isNull);
  });

  test(
    'guarda solo el correo, con la clave propia, y lo lee una app que se abre de nuevo',
    () async {
      await repo.guardar('  ana@example.com ');

      expect(almacen.contenido, {ClaveSegura.ultimoCorreo: 'ana@example.com'});
      final reabierto = UltimoCorreoRepositoryImpl(almacen, logger: loggerMudo());
      expect(await reabierto.leer(), 'ana@example.com');
    },
  );

  test('guardar otro correo reemplaza al anterior', () async {
    await repo.guardar('ana@example.com');
    await repo.guardar('luis@example.com');

    expect(await repo.leer(), 'luis@example.com');
  });

  test('un correo vacío no guarda nada ni pisa el que había', () async {
    await repo.guardar('ana@example.com');
    await repo.guardar('   ');

    expect(await repo.leer(), 'ana@example.com');
  });

  test('borrar lo olvida, y borrar sin nada guardado no falla', () async {
    await repo.guardar('ana@example.com');
    await repo.borrar();
    expect(await repo.leer(), isNull);

    await expectLater(repo.borrar(), completes);
  });

  test('un valor guardado en blanco se lee como sin correo', () async {
    await almacen.escribir(ClaveSegura.ultimoCorreo, '  ');

    expect(await repo.leer(), isNull);
  });

  test('guardar y borrar sin esperar: gana el borrado, aunque el guardado tarde', () async {
    final lento = _AlmacenLento();
    final repoLento = UltimoCorreoRepositoryImpl(lento, logger: loggerMudo());

    final guardado = repoLento.guardar('ana@example.com');
    final borrado = repoLento.borrar();
    await Future.wait([guardado, borrado]);

    expect(await repoLento.leer(), isNull);
  });

  test('borrar y guardar sin esperar: queda el último guardado', () async {
    await repo.guardar('ana@example.com');

    final borrado = repo.borrar();
    final guardado = repo.guardar('luis@example.com');
    await Future.wait([borrado, guardado]);

    expect(await repo.leer(), 'luis@example.com');
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('leer devuelve null en vez de lanzar', () async {
      expect(await repo.leer(), isNull);
    });

    test('guardar y borrar no lanzan (solo van al log)', () async {
      await expectLater(repo.guardar('ana@example.com'), completes);
      await expectLater(repo.borrar(), completes);
    });

    test('una falla no traba las operaciones siguientes', () async {
      await repo.guardar('ana@example.com');
      almacen.simularFalla = false;

      await repo.guardar('luis@example.com');

      expect(await repo.leer(), 'luis@example.com');
    });
  });

  test('UltimoCorreoEnMemoria guarda, reemplaza y borra', () async {
    final memoria = UltimoCorreoEnMemoria();
    expect(await memoria.leer(), isNull);

    await memoria.guardar('ana@example.com');
    expect(await memoria.leer(), 'ana@example.com');

    await memoria.borrar();
    expect(await memoria.leer(), isNull);
  });
}
