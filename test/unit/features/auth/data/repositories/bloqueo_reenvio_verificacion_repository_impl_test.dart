// Lo que el reenvío de verificación recuerda vive en el almacén seguro, en un JSON por dirección con
// el vencimiento de su candado (una hora) y de su espera (60 s) en UTC. Solo guarda lo vigente: cada
// lectura y cada guardado podan lo vencido y recortan lo que pasa de su tope, y la clave se borra
// cuando no queda nada. Las operaciones salen en el orden en que se piden (decisión de Cristian,
// 30/09, #221 y #239; seguimiento #249; poda y espera del alta, decisión del orquestador, 08/10,
// #325).
import 'dart:convert';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/reenvios_guardados.dart';
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

/// Almacén que se puede leer pero no escribir ni borrar: para ver que no se pisa nada.
final class _AlmacenSoloLectura implements AlmacenSeguro {
  _AlmacenSoloLectura(this._real);

  final AlmacenSeguroEnMemoria _real;
  bool escribio = false;

  @override
  Future<String?> leer(ClaveSegura clave) => _real.leer(clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    escribio = true;
    throw AlmacenSeguroException(operacion: 'escribir', clave: clave);
  }

  @override
  Future<void> borrar(ClaveSegura clave) async {
    escribio = true;
    throw AlmacenSeguroException(operacion: 'borrar', clave: clave);
  }

  @override
  Future<void> borrarTodo() async => throw const AlmacenSeguroException(operacion: 'borrarTodo');
}

/// Almacén que no se deja leer pero sí escribir: el caso que pisaría lo de las demás direcciones.
final class _AlmacenSinLectura implements AlmacenSeguro {
  _AlmacenSinLectura(this._real);

  final AlmacenSeguroEnMemoria _real;

  @override
  Future<String?> leer(ClaveSegura clave) async =>
      throw AlmacenSeguroException(operacion: 'leer', clave: clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) => _real.escribir(clave, valor);

  @override
  Future<void> borrar(ClaveSegura clave) => _real.borrar(clave);

  @override
  Future<void> borrarTodo() => _real.borrarTodo();
}

void main() {
  final ahora = DateTime.utc(2026, 10, 8, 10);
  final vence = ahora.add(const Duration(minutes: 60));
  final venceEspera = ahora.add(const Duration(seconds: 60));

  late AlmacenSeguroEnMemoria almacen;
  late BloqueoReenvioVerificacionRepositoryImpl repo;

  Map<String, dynamic> guardado() =>
      jsonDecode(almacen.contenido[ClaveSegura.bloqueoReenvioVerificacion]!)
          as Map<String, dynamic>;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin nada guardado, no hay candados ni esperas', () async {
    expect((await repo.leer(ahora: ahora)).estaVacio, isTrue);
    expect(almacen.contenido, isEmpty);
  });

  test('guarda el candado con su vencimiento en ISO 8601 UTC y la clave propia, y lo lee una app '
      'que se abre de nuevo', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);

    expect(almacen.contenido.keys, [ClaveSegura.bloqueoReenvioVerificacion]);
    expect(guardado(), {
      'ana@correo.com': {'bloqueo': '2026-10-08T11:00:00.000Z'},
    });
    final reabierto = BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
    final leido = await reabierto.leer(ahora: ahora);
    expect(leido.bloqueos, {'ana@correo.com': vence});
    expect(leido.esperas, isEmpty);
  });

  test('guarda la espera de 60 s de una dirección en su propio campo', () async {
    await repo.guardarEspera('ana@correo.com', venceEspera, ahora: ahora);

    expect(guardado(), {
      'ana@correo.com': {'espera': '2026-10-08T10:01:00.000Z'},
    });
    final leido = await repo.leer(ahora: ahora);
    expect(leido.esperas, {'ana@correo.com': venceEspera});
    expect(leido.bloqueos, isEmpty);
  });

  test('la misma dirección puede tener el candado y la espera a la vez, sin pisarse', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);
    await repo.guardarEspera('ana@correo.com', venceEspera, ahora: ahora);

    expect(guardado(), {
      'ana@correo.com': {
        'bloqueo': '2026-10-08T11:00:00.000Z',
        'espera': '2026-10-08T10:01:00.000Z',
      },
    });
    final leido = await repo.leer(ahora: ahora);
    expect(leido.bloqueos, {'ana@correo.com': vence});
    expect(leido.esperas, {'ana@correo.com': venceEspera});
  });

  test('el vencimiento vuelve en UTC y con los microsegundos que tenía', () async {
    final conMicros = DateTime.utc(2026, 10, 8, 10, 30, 0, 123, 456);
    await repo.guardar('ana@correo.com', conMicros, ahora: ahora);

    final leido = (await repo.leer(ahora: ahora)).bloqueos['ana@correo.com']!;

    expect(leido.isUtc, isTrue);
    expect(leido, conMicros);
  });

  test('un vencimiento local se guarda como el mismo instante en UTC', () async {
    final local = DateTime(2026, 10, 8, 11);

    await repo.guardar('ana@correo.com', local, ahora: ahora);

    expect((guardado()['ana@correo.com'] as Map)['bloqueo'], endsWith('Z'));
    expect((await repo.leer(ahora: ahora)).bloqueos['ana@correo.com'], local.toUtc());
  });

  test('cada dirección tiene lo suyo: guardar otra no pisa la primera', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);
    final despues = vence.add(const Duration(minutes: 5));

    await repo.guardar('luis@correo.com', despues, ahora: ahora.add(const Duration(minutes: 5)));

    expect((await repo.leer(ahora: ahora.add(const Duration(minutes: 5)))).bloqueos, {
      'ana@correo.com': vence,
      'luis@correo.com': despues,
    });
  });

  test('guardar la misma dirección reemplaza su vencimiento', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);
    final mas = ahora.add(const Duration(minutes: 10));
    final despues = mas.add(const Duration(minutes: 60));

    await repo.guardar('ana@correo.com', despues, ahora: mas);

    expect((await repo.leer(ahora: mas)).bloqueos, {'ana@correo.com': despues});
  });

  test('cada guardado descarta lo que ya venció a la hora que dice el llamador, así el almacén no '
      'crece', () async {
    await repo.guardar('vieja@correo.com', vence, ahora: ahora);
    await repo.guardarEspera('vieja@correo.com', venceEspera, ahora: ahora);
    // El de «media» se guardó 30 min después: vence a los 90 min, ya pasado el de «vieja».
    final mitad = ahora.add(const Duration(minutes: 30));
    await repo.guardar('media@correo.com', mitad.add(const Duration(minutes: 60)), ahora: mitad);

    // Pasa más de una hora: lo de «vieja» ya venció, el de «media» no.
    final mas = ahora.add(const Duration(minutes: 70));
    await repo.guardar('nueva@correo.com', mas.add(const Duration(minutes: 60)), ahora: mas);

    expect(guardado().keys, ['media@correo.com', 'nueva@correo.com']);
  });

  group('leer poda lo vencido y lo deja podado en el teléfono (#325)', () {
    test('un candado vencido no sale de leer y la clave queda borrada', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);

      final leido = await repo.leer(ahora: vence);

      expect(leido.estaVacio, isTrue);
      expect(
        almacen.contenido.containsKey(ClaveSegura.bloqueoReenvioVerificacion),
        isFalse,
        reason: 'sin nada vigente no queda ninguna dirección guardada',
      );
    });

    test('una espera vencida tampoco, y la clave se va', () async {
      await repo.guardarEspera('ana@correo.com', venceEspera, ahora: ahora);

      final leido = await repo.leer(ahora: venceEspera);

      expect(leido.estaVacio, isTrue);
      expect(almacen.contenido, isEmpty);
    });

    test('con un candado vencido y otro vigente, queda solo el vigente', () async {
      await repo.guardar('vieja@correo.com', vence, ahora: ahora);
      final mas = ahora.add(const Duration(minutes: 30));
      await repo.guardar('nueva@correo.com', mas.add(const Duration(minutes: 60)), ahora: mas);

      final leido = await repo.leer(ahora: vence.add(const Duration(minutes: 1)));

      expect(leido.bloqueos.keys, ['nueva@correo.com']);
      expect(guardado().keys, ['nueva@correo.com']);
    });

    test('de la dirección con candado vencido y espera vigente queda solo la espera', () async {
      await repo.guardar('ana@correo.com', ahora.add(const Duration(seconds: 30)), ahora: ahora);
      await repo.guardarEspera('ana@correo.com', venceEspera, ahora: ahora);

      await repo.leer(ahora: ahora.add(const Duration(seconds: 40)));

      expect(guardado(), {
        'ana@correo.com': {'espera': '2026-10-08T10:01:00.000Z'},
      });
    });

    test('un vencimiento que pasa de su tope se recorta una vez y queda recortado: el reloj '
        'atrasado no estira el candado ni lo corre una hora más en cada apertura', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);
      await repo.guardarEspera('ana@correo.com', venceEspera, ahora: ahora);

      // El reloj se atrasó 3 horas: el vencimiento guardado queda a casi 4 horas.
      final atrasado = ahora.subtract(const Duration(hours: 3));
      final primera = await repo.leer(ahora: atrasado);

      expect(primera.bloqueos['ana@correo.com'], atrasado.add(const Duration(minutes: 60)));
      expect(primera.esperas['ana@correo.com'], atrasado.add(const Duration(seconds: 60)));
      expect(guardado()['ana@correo.com'], {
        'bloqueo': '2026-10-08T08:00:00.000Z',
        'espera': '2026-10-08T07:01:00.000Z',
      }, reason: 'el recorte quedó guardado');

      // Se abre de nuevo 10 minutos después: no se corre otra hora, sigue siendo lo mismo.
      final despues = await repo.leer(ahora: atrasado.add(const Duration(minutes: 10)));
      expect(despues.bloqueos['ana@correo.com'], atrasado.add(const Duration(minutes: 60)));
    });

    test('con el almacén roto al podar, igual devuelve lo vigente (la poda es un extra)', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);
      final soloLectura = _AlmacenSoloLectura(almacen);
      final repoSoloLectura = BloqueoReenvioVerificacionRepositoryImpl(
        soloLectura,
        logger: loggerMudo(),
      );

      final leido = await repoSoloLectura.leer(ahora: vence);

      expect(leido.estaVacio, isTrue);
      expect(soloLectura.escribio, isTrue, reason: 'lo intentó');
    });
  });

  test('no toca el correo de la última cuenta ni lo que está al lado', () async {
    await almacen.escribir(ClaveSegura.ultimoCorreo, 'ana@example.com');
    await almacen.escribir(ClaveSegura.ultimoEnvioRecuperacion, '2026-10-08T10:30:15.000Z');

    await repo.guardar('ana@correo.com', vence, ahora: ahora);
    await repo.leer(ahora: vence);
    await repo.olvidarTodo();

    expect(almacen.contenido[ClaveSegura.ultimoCorreo], 'ana@example.com');
    expect(almacen.contenido[ClaveSegura.ultimoEnvioRecuperacion], '2026-10-08T10:30:15.000Z');
  });

  group('olvidar', () {
    test('quita el candado y la espera de esa dirección y deja las demás', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);
      await repo.guardarEspera('ana@correo.com', venceEspera, ahora: ahora);
      await repo.guardar('luis@correo.com', vence, ahora: ahora);

      await repo.olvidar('ana@correo.com');

      final leido = await repo.leer(ahora: ahora);
      expect(leido.bloqueos, {'luis@correo.com': vence});
      expect(leido.esperas, isEmpty);
    });

    test('si era la única, la clave se borra', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);

      await repo.olvidar('ana@correo.com');

      expect(almacen.contenido, isEmpty);
    });

    test('olvidar una dirección que no estaba no cambia nada', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);

      await repo.olvidar('otra@correo.com');

      expect((await repo.leer(ahora: ahora)).bloqueos, {'ana@correo.com': vence});
    });

    test('olvidarTodo borra la lista entera', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);
      await repo.guardarEspera('luis@correo.com', venceEspera, ahora: ahora);

      await repo.olvidarTodo();

      expect(almacen.contenido, isEmpty);
      expect((await repo.leer(ahora: ahora)).estaVacio, isTrue);
    });

    test('olvidar no lanza con el almacén roto', () async {
      almacen.simularFalla = true;

      await expectLater(repo.olvidar('ana@correo.com'), completes);
      await expectLater(repo.olvidarTodo(), completes);
    });
  });

  group('un valor guardado que no se puede leer es «nada guardado» (no se inventa un bloqueo)', () {
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

        expect((await repo.leer(ahora: ahora)).estaVacio, isTrue);
      });
    }

    test('una fecha rota se saltea y las demás se leen', () async {
      await almacen.escribir(
        ClaveSegura.bloqueoReenvioVerificacion,
        jsonEncode({
          'rota@correo.com': {'bloqueo': 'mañana'},
          'numero@correo.com': {'bloqueo': 5},
          'nula@correo.com': null,
          'ana@correo.com': {'bloqueo': '2026-10-08T11:00:00.000Z'},
          '': {'bloqueo': '2026-10-08T11:00:00.000Z'},
        }),
      );

      expect((await repo.leer(ahora: ahora)).bloqueos, {'ana@correo.com': vence});
    });

    test('una fecha con espacios alrededor igual se lee', () async {
      await almacen.escribir(
        ClaveSegura.bloqueoReenvioVerificacion,
        jsonEncode({
          'ana@correo.com': {'bloqueo': ' 2026-10-08T11:00:00.000Z\n'},
        }),
      );

      expect((await repo.leer(ahora: ahora)).bloqueos, {'ana@correo.com': vence});
    });

    test('la forma de #249 (solo el candado, como texto) todavía se lee', () async {
      await almacen.escribir(
        ClaveSegura.bloqueoReenvioVerificacion,
        jsonEncode({'ana@correo.com': '2026-10-08T11:00:00.000Z'}),
      );

      expect((await repo.leer(ahora: ahora)).bloqueos, {'ana@correo.com': vence});
    });

    test('y un guardado nuevo lo pisa', () async {
      await almacen.escribir(ClaveSegura.bloqueoReenvioVerificacion, 'basura');

      await repo.guardar('ana@correo.com', vence, ahora: ahora);

      expect((await repo.leer(ahora: ahora)).bloqueos, {'ana@correo.com': vence});
    });
  });

  test(
    'guardar y leer sin esperar: la lectura ve el candado nuevo, aunque el guardado tarde',
    () async {
      final lento = _AlmacenLento();
      final repoLento = BloqueoReenvioVerificacionRepositoryImpl(lento, logger: loggerMudo());

      final guardadoEnVuelo = repoLento.guardar('ana@correo.com', vence, ahora: ahora);
      final lectura = repoLento.leer(ahora: ahora);
      await guardadoEnVuelo;

      expect((await lectura).bloqueos, {'ana@correo.com': vence});
    },
  );

  test('dos guardados seguidos sin esperar de direcciones distintas: quedan los dos', () async {
    final lento = _AlmacenLento();
    final repoLento = BloqueoReenvioVerificacionRepositoryImpl(lento, logger: loggerMudo());

    final primero = repoLento.guardar('ana@correo.com', vence, ahora: ahora);
    final segundo = repoLento.guardarEspera('luis@correo.com', venceEspera, ahora: ahora);
    await Future.wait([primero, segundo]);

    final leido = await repoLento.leer(ahora: ahora);
    expect(leido.bloqueos.keys, ['ana@correo.com']);
    expect(leido.esperas.keys, ['luis@correo.com']);
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('leer devuelve vacío en vez de lanzar', () async {
      expect((await repo.leer(ahora: ahora)).estaVacio, isTrue);
    });

    test('guardar no lanza (solo va al log, sin la dirección)', () async {
      await expectLater(repo.guardar('ana@correo.com', vence, ahora: ahora), completes);
      await expectLater(repo.guardarEspera('ana@correo.com', venceEspera, ahora: ahora), completes);
    });

    test('una falla no traba las operaciones siguientes', () async {
      await repo.guardar('ana@correo.com', vence, ahora: ahora);
      almacen.simularFalla = false;

      await repo.guardar('luis@correo.com', vence, ahora: ahora);

      expect((await repo.leer(ahora: ahora)).bloqueos, {'luis@correo.com': vence});
    });
  });

  test('si el almacén no se deja leer al guardar, no se escribe: pisaría el candado de las otras '
      'direcciones', () async {
    await repo.guardar('ana@correo.com', vence, ahora: ahora);
    final sinLectura = _AlmacenSinLectura(almacen);
    final repoSinLectura = BloqueoReenvioVerificacionRepositoryImpl(
      sinLectura,
      logger: loggerMudo(),
    );

    await repoSinLectura.guardar('luis@correo.com', vence, ahora: ahora);
    await repoSinLectura.guardarEspera('luis@correo.com', venceEspera, ahora: ahora);
    await repoSinLectura.olvidar('luis@correo.com');

    expect(guardado().keys, ['ana@correo.com'], reason: 'el de Ana sigue ahí');
  });

  group('BloqueoReenvioVerificacionEnMemoria', () {
    test('guarda en UTC, reemplaza por dirección y descarta lo vencido', () async {
      final memoria = BloqueoReenvioVerificacionEnMemoria();
      expect((await memoria.leer(ahora: ahora)).estaVacio, isTrue);

      await memoria.guardar('ana@correo.com', vence, ahora: ahora);
      await memoria.guardar('luis@correo.com', vence.toLocal(), ahora: ahora);
      final leido = await memoria.leer(ahora: ahora);
      expect(leido.bloqueos['luis@correo.com']!.isUtc, isTrue);
      expect(leido.bloqueos.keys, unorderedEquals(['ana@correo.com', 'luis@correo.com']));

      final mas = ahora.add(const Duration(minutes: 90));
      await memoria.guardar('ana@correo.com', mas.add(const Duration(minutes: 60)), ahora: mas);
      expect((await memoria.leer(ahora: mas)).bloqueos.keys, ['ana@correo.com']);
    });

    test('guarda esperas, olvida una dirección o todo, y recorta lo que pasa de su tope', () async {
      final memoria = BloqueoReenvioVerificacionEnMemoria();
      await memoria.guardarEspera('ana@correo.com', venceEspera, ahora: ahora);
      await memoria.guardar('luis@correo.com', vence, ahora: ahora);

      expect((await memoria.leer(ahora: ahora)).esperas, {'ana@correo.com': venceEspera});

      await memoria.olvidar('ana@correo.com');
      expect((await memoria.leer(ahora: ahora)).esperas, isEmpty);
      expect((await memoria.leer(ahora: ahora)).bloqueos, {'luis@correo.com': vence});

      final atrasado = ahora.subtract(const Duration(hours: 3));
      expect(
        (await memoria.leer(ahora: atrasado)).bloqueos['luis@correo.com'],
        atrasado.add(bloqueoReenvioVerificacion),
      );

      await memoria.olvidarTodo();
      expect((await memoria.leer(ahora: ahora)).estaVacio, isTrue);
    });

    test('puede arrancar con candados y esperas ya guardados', () async {
      final memoria = BloqueoReenvioVerificacionEnMemoria.con(
        bloqueos: {'ana@correo.com': vence.toLocal()},
        esperas: {'luis@correo.com': venceEspera.toLocal()},
      );
      final leido = await memoria.leer(ahora: ahora);

      expect(leido.bloqueos, {'ana@correo.com': vence});
      expect(leido.esperas, {'luis@correo.com': venceEspera});
      expect(
        (await BloqueoReenvioVerificacionEnMemoria({
          'ana@correo.com': vence,
        }).leer(ahora: ahora)).bloqueos,
        {'ana@correo.com': vence},
      );
    });
  });
}
