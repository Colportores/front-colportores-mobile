// Las inscripciones con zona leídas de las réplicas locales del pull (HU-CAM-006, #251 y #274): sin
// red, con las filas entrando por el mismo `DriftLocalStore` del pull de catálogos.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/auth/data/datasources/inscripciones_con_zona_local_data_source.dart';
import 'package:colportores_mobile/features/auth/domain/entities/inscripcion_con_zona.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/replica_de_campanias.dart';

const _usuario = 'col-1';

InscripcionConZona _inscripcion({
  String id = 'insc-1',
  String campaniaId = 'camp-1',
  String campania = 'Verano 2026',
  String? zonaId,
  String? zona,
  bool dadaDeBaja = false,
}) => InscripcionConZona(
  id: id,
  campaniaId: campaniaId,
  campaniaNombre: campania,
  zonaId: zonaId,
  zonaNombre: zona,
  dadaDeBaja: dadaDeBaja,
);

Map<String, Object?> _centro({bool deBaja = false}) => filaZona(
  'z-centro',
  'Centro',
  campaniaCiudad: 'cc-mvd',
  latSur: -34.92,
  latNorte: -34.88,
  lonOeste: -56.20,
  lonEste: -56.15,
  deBaja: deBaja,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;
  late InscripcionesConZonaLocal fuente;
  var hoy = DateTime.utc(2026, 10, 27, 15);

  setUp(() {
    hoy = DateTime.utc(2026, 10, 27, 15);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    fuente = InscripcionesConZonaLocal(db, ahora: () => hoy);
  });
  tearDown(() => db.close());

  /// Se suscribe y junta lo que emite.
  Future<List<List<InscripcionConZona>>> escuchar({String usuario = _usuario}) async {
    final emisiones = <List<InscripcionConZona>>[];
    final suscripcion = fuente.observar(usuario).listen(emisiones.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue(times: 100);
    return emisiones;
  }

  Future<void> asentar() => pumpEventQueue(times: 100);

  group('lo que emite', () {
    test(
      'al suscribirse, el estado de hoy: la inscripción con el nombre de su campaña y de su zona',
      () async {
        await replica.bajar({
          'campania': [filaCampania('camp-1', 'Verano 2026')],
          'zona': [_centro()],
          'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
        });

        final emisiones = await escuchar();

        expect(emisiones, [
          [_inscripcion(zonaId: 'z-centro', zona: 'Centro')],
        ]);
      },
    );

    test('sin ninguna inscripción emite la lista vacía', () async {
      expect(await escuchar(), [isEmpty]);
    });

    test('un pull que cambia, quita o da de baja la zona vuelve a emitir', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
        'zona': [_centro()],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
      });
      final emisiones = await escuchar();

      await replica.bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });
      await asentar();
      await replica.bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', deBaja: true)],
      });
      await asentar();

      expect(emisiones.last, [_inscripcion(dadaDeBaja: true)]);
      expect(emisiones.map((e) => e.single.zonaId), ['z-centro', null, null]);
    });

    test(
      'con la zona asignada y todavía sin bajar, emite el id sin nombre; cuando llega, el nombre',
      () async {
        await replica.bajar({
          'campania': [filaCampania('camp-1', 'Verano 2026')],
          'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
        });
        final emisiones = await escuchar();
        expect(emisiones.single, [_inscripcion(zonaId: 'z-centro')]);

        await replica.bajar({
          'zona': [_centro()],
        });
        await asentar();

        expect(emisiones.last, [_inscripcion(zonaId: 'z-centro', zona: 'Centro')]);
      },
    );

    test('una zona dada de baja no tiene nombre con que avisar', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
        'zona': [_centro(deBaja: true)],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
      });

      expect((await escuchar()).single, [_inscripcion(zonaId: 'z-centro')]);
    });

    test(
      'la inscripción cuya campaña todavía no llegó no se emite; cuando llega, aparece',
      () async {
        await replica.bajar({
          'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
        });
        final emisiones = await escuchar();
        expect(emisiones.single, isEmpty);

        await replica.bajar({
          'campania': [filaCampania('camp-1', 'Verano 2026')],
        });
        await asentar();

        expect(emisiones.last, [_inscripcion()]);
      },
    );
  });

  group('qué inscripciones entran', () {
    test('incluye las dadas de baja (el detector las anota sin avisar)', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', deBaja: true)],
      });

      expect((await escuchar()).single, [_inscripcion(dadaDeBaja: true)]);
    });

    test(
      'solo las de campañas que no terminaron: en curso, por empezar y sin fecha de fin sí; terminada o dada de baja, no',
      () async {
        await replica.bajar({
          'campania': [
            filaCampania('camp-1', 'En curso'),
            filaCampania('camp-2', 'Por empezar', inicio: '2026-12-01', fin: '2027-02-28'),
            filaCampania('camp-3', 'Permanente', fin: null),
            filaCampania('camp-4', 'Terminó ayer', fin: '2026-10-26'),
            filaCampania('camp-5', 'Dada de baja', deBaja: true),
            filaCampania('camp-6', 'Termina hoy', fin: '2026-10-27'),
          ],
          'campania_colportor': [
            for (var i = 1; i <= 6; i++) filaInscripcion('insc-$i', campania: 'camp-$i'),
          ],
        });

        final emisiones = await escuchar();

        expect(
          [for (final i in emisiones.single) i.campaniaNombre],
          ['En curso', 'Por empezar', 'Permanente', 'Termina hoy'],
        );
      },
    );

    test('el día se vuelve a mirar en cada emisión: la que terminaba hoy sale mañana', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Termina hoy', fin: '2026-10-27')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });
      final emisiones = await escuchar();
      expect(emisiones.single, hasLength(1));

      hoy = DateTime.utc(2026, 10, 28, 3);
      await replica.bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
      });
      await asentar();

      expect(emisiones.last, isEmpty);
    });

    test('solo las del usuario', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
        'campania_colportor': [
          filaInscripcion('insc-1', campania: 'camp-1'),
          filaInscripcion('insc-2', campania: 'camp-1', usuario: 'col-2'),
        ],
      });

      expect([for (final i in (await escuchar()).single) i.id], ['insc-1']);
      expect([for (final i in (await escuchar(usuario: 'col-2')).single) i.id], ['insc-2']);
    });

    test('en el orden en que se inscribió, y por id si fue a la vez', () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'A'), filaCampania('camp-2', 'B')],
        'campania_colportor': [
          filaInscripcion('insc-b', campania: 'camp-2'),
          filaInscripcion('insc-a', campania: 'camp-1'),
        ],
      });

      expect([for (final i in (await escuchar()).single) i.id], ['insc-a', 'insc-b']);
    });
  });

  test('sin la base abierta (no hay sesión) no hay nada que avisar: lista vacía', () async {
    final sinBase = InscripcionesConZonaLocal(null);

    expect(await sinBase.observar(_usuario).toList(), [isEmpty]);
  });
}
