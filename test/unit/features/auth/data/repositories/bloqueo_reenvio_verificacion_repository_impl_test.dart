// Los candados del reenvío de verificación viven en el almacén seguro, en un JSON por dirección con
// su vencimiento en UTC, y las operaciones salen en el orden en que se piden (decisión de Cristian,
// 30/09, #221 y #239; seguimiento #249).
import 'dart:convert';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
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
  final ahora = DateTime.utc(2026, 10, 8, 10);
  final vence = ahora.add(const Duration(minutes: 60));

  late AlmacenSeguroEnMemoria almacen;
  late BloqueoReenvioVerificacionRepositoryImpl repo;

  Map<String, dynamic> guardado() =>
      jsonDecode(almacen.contenido[ClaveSegura.bloqueoReenvioVerificacion]!)
          as Map<String, dynamic>;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin nada guardado, no hay candados', () async {
    expect(await repo.leer(), isEmpty);
  });

  test('guarda la dirección con su vencimiento en ISO 8601 UTC y la clave propia, y la lee una '
      'app que se abre de nuevo', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);

    expect(almacen.contenido.keys, [ClaveSegura.bloqueoReenvioVerificacion]);
    expect(guardado(), {'ana@correo.com': '2026-10-08T11:00:00.000Z'});
    final reabierto = BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
    expect(await reabierto.leer(), {'ana@correo.com': vence});
  });

  test('el vencimiento vuelve en UTC y con los microsegundos que tenía', () async {
    final conMicros = DateTime.utc(2026, 10, 8, 11, 0, 0, 123, 456);
    await repo.guardar('ana@correo.com', conMicros, ahora: ahora);

    final leido = (await repo.leer())['ana@correo.com']!;

    expect(leido.isUtc, isTrue);
    expect(leido, conMicros);
  });

  test('un vencimiento local se guarda como el mismo instante en UTC', () async {
    final local = DateTime(2026, 10, 8, 11);

    await repo.guardar('ana@correo.com', local, ahora: ahora);

    expect(guardado()['ana@correo.com'], endsWith('Z'));
    expect((await repo.leer())['ana@correo.com'], local.toUtc());
  });

  test('cada dirección tiene su candado: guardar otra no pisa la primera', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);
    final despues = vence.add(const Duration(minutes: 5));

    await repo.guardar('luis@correo.com', despues, ahora: ahora.add(const Duration(minutes: 5)));

    expect(await repo.leer(), {'ana@correo.com': vence, 'luis@correo.com': despues});
  });

  test('guardar la misma dirección reemplaza su vencimiento', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);
    final despues = vence.add(const Duration(minutes: 70));

    await repo.guardar('ana@correo.com', despues, ahora: vence.add(const Duration(minutes: 10)));

    expect(await repo.leer(), {'ana@correo.com': despues});
  });

  test('cada guardado descarta los candados que ya vencieron, así el almacén no crece', () async {
    await repo.guardar('vieja@correo.com', vence, ahora: ahora);
    await repo.guardar('media@correo.com', vence.add(const Duration(minutes: 30)), ahora: ahora);

    // Pasa más de una hora: el de «vieja» ya venció, el de «media» no.
    final mas = ahora.add(const Duration(minutes: 70));
    await repo.guardar('nueva@correo.com', mas.add(const Duration(minutes: 60)), ahora: mas);

    expect(guardado().keys, ['media@correo.com', 'nueva@correo.com']);
  });

  test(
    'leer devuelve también los vencidos: decidir qué hacer con ellos es del que consulta',
    () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);

      expect(await repo.leer(), {'ana@correo.com': vence});
    },
  );

  test('no toca el correo de la última cuenta ni lo que está al lado', () async {
    await almacen.escribir(ClaveSegura.ultimoCorreo, 'ana@example.com');
    await almacen.escribir(ClaveSegura.ultimoEnvioRecuperacion, '2026-10-08T10:30:15.000Z');

    await repo.guardar('ana@correo.com', vence, ahora: ahora);

    expect(almacen.contenido[ClaveSegura.ultimoCorreo], 'ana@example.com');
    expect(almacen.contenido[ClaveSegura.ultimoEnvioRecuperacion], '2026-10-08T10:30:15.000Z');
  });

  group('un valor guardado que no se puede leer es «sin candados» (no se inventa un bloqueo)', () {
    for (final (nombre, valor) in const [
      ('vacío', ''),
      ('en blanco', '  '),
      ('con texto cualquiera', 'ayer'),
      ('con el JSON a medias', '{"ana@correo.com": "2026-10'),
      ('con una lista en vez de un objeto', '["ana@correo.com"]'),
      ('con un número', '42'),
      ('con null', 'null'),
    ]) {
      test(nombre, () async {
        await almacen.escribir(ClaveSegura.bloqueoReenvioVerificacion, valor);

        expect(await repo.leer(), isEmpty);
      });
    }

    test('una fecha rota se saltea y las demás se leen', () async {
      await almacen.escribir(
        ClaveSegura.bloqueoReenvioVerificacion,
        jsonEncode({
          'rota@correo.com': 'mañana',
          'numero@correo.com': 5,
          'nula@correo.com': null,
          'ana@correo.com': '2026-10-08T11:00:00.000Z',
          '': '2026-10-08T11:00:00.000Z',
        }),
      );

      expect(await repo.leer(), {'ana@correo.com': vence});
    });

    test('una fecha con espacios alrededor igual se lee', () async {
      await almacen.escribir(
        ClaveSegura.bloqueoReenvioVerificacion,
        jsonEncode({'ana@correo.com': ' 2026-10-08T11:00:00.000Z\n'}),
      );

      expect(await repo.leer(), {'ana@correo.com': vence});
    });

    test('y un guardado nuevo lo pisa', () async {
      await almacen.escribir(ClaveSegura.bloqueoReenvioVerificacion, 'basura');

      await repo.guardar('ana@correo.com', vence, ahora: ahora);

      expect(await repo.leer(), {'ana@correo.com': vence});
    });
  });

  test(
    'guardar y leer sin esperar: la lectura ve el candado nuevo, aunque el guardado tarde',
    () async {
      final lento = _AlmacenLento();
      final repoLento = BloqueoReenvioVerificacionRepositoryImpl(lento, logger: loggerMudo());

      final guardadoEnVuelo = repoLento.guardar('ana@correo.com', vence, ahora: ahora);
      final lectura = repoLento.leer();
      await guardadoEnVuelo;

      expect(await lectura, {'ana@correo.com': vence});
    },
  );

  test('dos guardados seguidos sin esperar de direcciones distintas: quedan los dos', () async {
    final lento = _AlmacenLento();
    final repoLento = BloqueoReenvioVerificacionRepositoryImpl(lento, logger: loggerMudo());

    final primero = repoLento.guardar('ana@correo.com', vence, ahora: ahora);
    final segundo = repoLento.guardar('luis@correo.com', vence, ahora: ahora);
    await Future.wait([primero, segundo]);

    expect((await repoLento.leer()).keys, unorderedEquals(['ana@correo.com', 'luis@correo.com']));
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('leer devuelve vacío en vez de lanzar', () async {
      expect(await repo.leer(), isEmpty);
    });

    test('guardar no lanza (solo va al log, sin la dirección)', () async {
      await expectLater(repo.guardar('ana@correo.com', vence, ahora: ahora), completes);
    });

    test('una falla no traba las operaciones siguientes', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);
      almacen.simularFalla = false;

      await repo.guardar('luis@correo.com', vence, ahora: ahora);

      expect(await repo.leer(), {'luis@correo.com': vence});
    });
  });

  group('BloqueoReenvioVerificacionEnMemoria', () {
    test('guarda en UTC, reemplaza por dirección y descarta lo vencido', () async {
      final memoria = BloqueoReenvioVerificacionEnMemoria();
      expect(await memoria.leer(), isEmpty);

      await memoria.guardar('ana@correo.com', vence, ahora: ahora);
      await memoria.guardar('luis@correo.com', vence.toLocal(), ahora: ahora);
      expect((await memoria.leer())['luis@correo.com']!.isUtc, isTrue);
      expect((await memoria.leer()).keys, unorderedEquals(['ana@correo.com', 'luis@correo.com']));

      final mas = ahora.add(const Duration(minutes: 90));
      await memoria.guardar('ana@correo.com', mas.add(const Duration(minutes: 60)), ahora: mas);
      expect((await memoria.leer()).keys, ['ana@correo.com']);
    });

    test('puede arrancar con candados ya guardados', () async {
      final memoria = BloqueoReenvioVerificacionEnMemoria({'ana@correo.com': vence.toLocal()});

      expect(await memoria.leer(), {'ana@correo.com': vence});
    });
  });
}
