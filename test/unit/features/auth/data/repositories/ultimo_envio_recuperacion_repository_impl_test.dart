// La hora del último enlace de recuperación pedido vive en el almacén seguro, sola y en UTC, y las
// operaciones salen en el orden en que se piden (decisión de Cristian, 02/10, #223; seguimiento
// #281).
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_envio_recuperacion_repository_impl.dart';
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
  final envio = DateTime.utc(2026, 10, 8, 10, 30, 15);

  late AlmacenSeguroEnMemoria almacen;
  late UltimoEnvioRecuperacionRepositoryImpl repo;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = UltimoEnvioRecuperacionRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin nada guardado, no hay hora del último envío', () async {
    expect(await repo.leer(), isNull);
  });

  test('guarda solo la hora, en ISO 8601 UTC y con la clave propia, y la lee una app que se abre '
      'de nuevo', () async {
    await repo.guardar(envio);

    expect(almacen.contenido, {ClaveSegura.ultimoEnvioRecuperacion: '2026-10-08T10:30:15.000Z'});
    final reabierto = UltimoEnvioRecuperacionRepositoryImpl(almacen, logger: loggerMudo());
    expect(await reabierto.leer(), envio);
  });

  test('la hora vuelve en UTC y con los microsegundos que tenía', () async {
    final conMicros = DateTime.utc(2026, 10, 8, 10, 30, 15, 123, 456);
    await repo.guardar(conMicros);

    final leida = (await repo.leer())!;

    expect(leida.isUtc, isTrue);
    expect(leida, conMicros);
  });

  test('una hora local se guarda como el mismo instante en UTC', () async {
    final local = DateTime(2026, 10, 8, 10, 30, 15);

    await repo.guardar(local);

    expect(almacen.contenido[ClaveSegura.ultimoEnvioRecuperacion], endsWith('Z'));
    expect(await repo.leer(), local.toUtc());
  });

  test('guardar otra hora reemplaza a la anterior', () async {
    await repo.guardar(envio);
    final despues = envio.add(const Duration(minutes: 3));
    await repo.guardar(despues);

    expect(await repo.leer(), despues);
  });

  test('no toca el correo de la última cuenta ni el cierre que están al lado', () async {
    await almacen.escribir(ClaveSegura.ultimoCorreo, 'ana@example.com');
    await almacen.escribir(ClaveSegura.cierreForzado, 'inactividad|2026-10-07T08:02:30.000Z');

    await repo.guardar(envio);

    expect(almacen.contenido, {
      ClaveSegura.ultimoCorreo: 'ana@example.com',
      ClaveSegura.cierreForzado: 'inactividad|2026-10-07T08:02:30.000Z',
      ClaveSegura.ultimoEnvioRecuperacion: '2026-10-08T10:30:15.000Z',
    });
  });

  test('no guarda el correo ni nada de la cuenta: la hora es el único dato', () async {
    await repo.guardar(envio);

    expect(almacen.contenido.keys, [ClaveSegura.ultimoEnvioRecuperacion]);
    expect(almacen.contenido.values.single, isNot(contains('@')));
  });

  group('un valor guardado que no se puede leer es «no hay envío» (no se inventa una espera)', () {
    for (final (nombre, valor) in const [
      ('en blanco', '  '),
      ('vacío', ''),
      ('con texto cualquiera', 'ayer'),
      ('con la fecha a medias', '2026-10-08T'),
      ('con letras en la fecha', '2026-10-08Tdiez:30:15Z'),
    ]) {
      test(nombre, () async {
        await almacen.escribir(ClaveSegura.ultimoEnvioRecuperacion, valor);

        expect(await repo.leer(), isNull);
      });
    }

    test('con espacios alrededor, igual se lee', () async {
      await almacen.escribir(ClaveSegura.ultimoEnvioRecuperacion, ' 2026-10-08T10:30:15.000Z\n');

      expect(await repo.leer(), envio);
    });

    test('una fecha sin huso se toma como hora local y vuelve en UTC', () async {
      await almacen.escribir(ClaveSegura.ultimoEnvioRecuperacion, '2026-10-08T10:30:15');

      final leida = (await repo.leer())!;

      expect(leida.isUtc, isTrue);
      expect(leida, DateTime(2026, 10, 8, 10, 30, 15).toUtc());
    });

    test('y un envío nuevo lo reemplaza', () async {
      await almacen.escribir(ClaveSegura.ultimoEnvioRecuperacion, 'basura');

      await repo.guardar(envio);

      expect(await repo.leer(), envio);
    });
  });

  test(
    'guardar y leer sin esperar: la lectura ve la hora nueva, aunque el guardado tarde',
    () async {
      final lento = _AlmacenLento();
      final repoLento = UltimoEnvioRecuperacionRepositoryImpl(lento, logger: loggerMudo());

      final guardado = repoLento.guardar(envio);
      final lectura = repoLento.leer();
      await guardado;

      expect(await lectura, envio);
    },
  );

  test('dos guardados seguidos sin esperar: queda el último', () async {
    final lento = _AlmacenLento();
    final repoLento = UltimoEnvioRecuperacionRepositoryImpl(lento, logger: loggerMudo());
    final despues = envio.add(const Duration(seconds: 61));

    final primero = repoLento.guardar(envio);
    final segundo = repoLento.guardar(despues);
    await Future.wait([primero, segundo]);

    expect(await repoLento.leer(), despues);
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('leer devuelve null en vez de lanzar', () async {
      expect(await repo.leer(), isNull);
    });

    test('guardar no lanza (solo va al log)', () async {
      await expectLater(repo.guardar(envio), completes);
    });

    test('una falla no traba las operaciones siguientes', () async {
      await repo.guardar(envio);
      almacen.simularFalla = false;

      await repo.guardar(envio.add(const Duration(seconds: 5)));

      expect(await repo.leer(), envio.add(const Duration(seconds: 5)));
    });
  });

  test('UltimoEnvioRecuperacionEnMemoria guarda en UTC y reemplaza', () async {
    final memoria = UltimoEnvioRecuperacionEnMemoria();
    expect(await memoria.leer(), isNull);

    await memoria.guardar(envio);
    expect(await memoria.leer(), envio);

    final local = DateTime(2026, 10, 9, 8);
    await memoria.guardar(local);
    expect((await memoria.leer())!.isUtc, isTrue);
    expect(await memoria.leer(), local.toUtc());

    expect(await UltimoEnvioRecuperacionEnMemoria(envio).leer(), envio);
  });
}
