// La zona de cada inscripción la última vez que se le avisó al colportor vive en el almacén seguro,
// en un JSON `{"<inscripción>": "<zona>" | null}`, y las operaciones salen en el orden en que se
// piden (HU-CAM-006, #251).
import 'dart:convert';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/zonas_avisadas_repository_impl.dart';
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
  late ZonasAvisadasRepositoryImpl repo;

  Map<String, dynamic> guardado() =>
      jsonDecode(almacen.contenido[ClaveSegura.zonasAvisadas]!) as Map<String, dynamic>;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = ZonasAvisadasRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin nada guardado, no hay zonas avisadas', () async {
    expect(await repo.leer(), isEmpty);
  });

  test('anota la zona de cada inscripción (null = sin zona) en la clave propia, y la lee una app '
      'que se abre de nuevo', () async {
    await repo.anotar({'insc-1': 'z-centro', 'insc-2': null});

    expect(almacen.contenido.keys, [ClaveSegura.zonasAvisadas]);
    expect(guardado(), {'insc-1': 'z-centro', 'insc-2': null});
    final reabierto = ZonasAvisadasRepositoryImpl(almacen, logger: loggerMudo());
    expect(await reabierto.leer(), {'insc-1': 'z-centro', 'insc-2': null});
  });

  test('anotar suma y pisa por inscripción, sin tocar las demás', () async {
    await repo.anotar({'insc-1': 'z-centro', 'insc-2': 'z-norte'});

    await repo.anotar({'insc-1': null, 'insc-3': 'z-sur'});

    expect(await repo.leer(), {'insc-1': null, 'insc-2': 'z-norte', 'insc-3': 'z-sur'});
  });

  test('anotar nada no escribe (ni crea la clave)', () async {
    await repo.anotar(const {});

    expect(almacen.contenido, isEmpty);
  });

  group(
    'un valor guardado que no se puede leer es «nada avisado» (se avisa de más, no de menos)',
    () {
      for (final (nombre, valor) in const [
        ('vacío', ''),
        ('en blanco', '  '),
        ('con texto cualquiera', 'ayer'),
        ('con el JSON a medias', '{"insc-1": "z-cen'),
        ('con una lista en vez de un objeto', '["insc-1"]'),
        ('con un número', '42'),
        ('con null', 'null'),
      ]) {
        test(nombre, () async {
          await almacen.escribir(ClaveSegura.zonasAvisadas, valor);

          expect(await repo.leer(), isEmpty);
        });
      }

      test('un par roto se saltea y los demás se leen', () async {
        await almacen.escribir(
          ClaveSegura.zonasAvisadas,
          jsonEncode({
            'numero': 5,
            'vacia': '',
            'lista': ['z'],
            '': 'z',
            'ok': 'z-centro',
            'sin': null,
          }),
        );

        expect(await repo.leer(), {'ok': 'z-centro', 'sin': null});
      });

      test('y una anotación nueva lo pisa', () async {
        await almacen.escribir(ClaveSegura.zonasAvisadas, 'basura');

        await repo.anotar({'insc-1': 'z-centro'});

        expect(await repo.leer(), {'insc-1': 'z-centro'});
      });
    },
  );

  test('anotar y leer sin esperar: la lectura ve lo anotado, aunque el guardado tarde', () async {
    final lento = _AlmacenLento();
    final repoLento = ZonasAvisadasRepositoryImpl(lento, logger: loggerMudo());

    final anotacion = repoLento.anotar({'insc-1': 'z-centro'});
    final lectura = repoLento.leer();
    await anotacion;

    expect(await lectura, {'insc-1': 'z-centro'});
  });

  test('dos anotaciones seguidas sin esperar de inscripciones distintas: quedan las dos', () async {
    final lento = _AlmacenLento();
    final repoLento = ZonasAvisadasRepositoryImpl(lento, logger: loggerMudo());

    final primera = repoLento.anotar({'insc-1': 'z-centro'});
    final segunda = repoLento.anotar({'insc-2': null});
    await Future.wait([primera, segunda]);

    expect(await repoLento.leer(), {'insc-1': 'z-centro', 'insc-2': null});
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('leer devuelve vacío en vez de lanzar', () async {
      expect(await repo.leer(), isEmpty);
    });

    test('anotar no lanza (solo va al log, sin ids)', () async {
      await expectLater(repo.anotar({'insc-1': 'z-centro'}), completes);
    });

    test('una falla no traba las operaciones siguientes', () async {
      await repo.anotar({'insc-1': 'z-centro'});
      almacen.simularFalla = false;

      await repo.anotar({'insc-2': 'z-norte'});

      expect(await repo.leer(), {'insc-2': 'z-norte'});
    });
  });

  group('ZonasAvisadasEnMemoria', () {
    test('anota, suma y pisa por inscripción', () async {
      final memoria = ZonasAvisadasEnMemoria();
      expect(await memoria.leer(), isEmpty);

      await memoria.anotar({'insc-1': 'z-centro', 'insc-2': null});
      await memoria.anotar({'insc-1': 'z-norte'});

      expect(await memoria.leer(), {'insc-1': 'z-norte', 'insc-2': null});
    });

    test('puede arrancar con zonas ya avisadas y devuelve una copia', () async {
      final memoria = ZonasAvisadasEnMemoria({'insc-1': 'z-centro'});

      final copia = await memoria.leer();
      copia['insc-9'] = 'otra';

      expect(await memoria.leer(), {'insc-1': 'z-centro'});
    });

    test('con fallaAlAnotar no guarda nada y no lanza', () async {
      final memoria = ZonasAvisadasEnMemoria()..fallaAlAnotar = true;

      await memoria.anotar({'insc-1': 'z-centro'});

      expect(await memoria.leer(), isEmpty);
    });
  });
}
