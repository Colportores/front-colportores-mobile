// Las campañas del colportor leídas de las réplicas locales del pull (HU-AUTH-008, #62 y #274): sin
// red, con las filas entrando por el mismo `DriftLocalStore` del pull de catálogos.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/auth/data/datasources/campanias_inscriptas_local_data_source.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/replica_de_campanias.dart';

const _usuario = 'col-1';

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
  late CampaniasInscriptasLocal fuente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    fuente = CampaniasInscriptasLocal(db);
  });
  tearDown(() => db.close());

  Future<List<List<CampaniaInscripta>?>> escuchar({String usuario = _usuario}) async {
    final emisiones = <List<CampaniaInscripta>?>[];
    final suscripcion = fuente.observar(usuario).listen(emisiones.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue(times: 100);
    return emisiones;
  }

  Future<void> asentar() => pumpEventQueue(times: 100);

  test('sin ninguna inscripción emite la lista vacía («se leyó y no hay»)', () async {
    expect(await escuchar(), [isEmpty]);
  });

  test('la inscripción con su campaña, sus fechas, su zona y la ciudad de la zona', () async {
    await replica.bajar({
      'ciudad': [filaCiudad('c-mvd', 'Montevideo', lat: -34.9, lon: -56.16)],
      'campania': [filaCampania('camp-1', 'Verano 2027', inicio: '2026-12-01', fin: '2027-02-28')],
      'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'c-mvd')],
      'zona': [_centro()],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
    });

    expect(await escuchar(), [
      [
        const CampaniaInscripta(
          campaniaId: 'camp-1',
          nombre: 'Verano 2027',
          fechaInicio: '2026-12-01',
          fechaFin: '2027-02-28',
          zona: 'Centro',
          ciudad: 'Montevideo',
        ),
      ],
    ]);
  });

  test('sin zona asignada (inscripto «sin zona») no hay zona ni ciudad', () async {
    await replica.bajar({
      'campania': [filaCampania('camp-1', 'Verano 2027', inicio: '2026-12-01')],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
    });

    final unica = (await escuchar()).single!.single;

    expect(unica.zona, isNull);
    expect(unica.ciudad, isNull);
    expect(unica.fechaFin, '2027-02-28');
  });

  test('con la zona asignada y todavía sin bajar: sin zona; cuando llega, aparece', () async {
    await replica.bajar({
      'campania': [filaCampania('camp-1', 'Verano 2027')],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
    });
    final emisiones = await escuchar();
    expect(emisiones.single!.single.zona, isNull);

    await replica.bajar({
      'ciudad': [filaCiudad('c-mvd', 'Montevideo', lat: -34.9, lon: -56.16)],
      'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'c-mvd')],
      'zona': [_centro()],
    });
    await asentar();

    expect(emisiones.last!.single.zona, 'Centro');
    expect(emisiones.last!.single.ciudad, 'Montevideo');
  });

  test('una zona dada de baja no cuenta: sin zona', () async {
    await replica.bajar({
      'ciudad': [filaCiudad('c-mvd', 'Montevideo', lat: -34.9, lon: -56.16)],
      'campania': [filaCampania('camp-1', 'Verano 2027')],
      'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'c-mvd')],
      'zona': [_centro(deBaja: true)],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-centro')],
    });

    final unica = (await escuchar()).single!.single;

    expect(unica.zona, isNull);
    expect(unica.ciudad, isNull);
  });

  test('solo las inscripciones propias, sin baja y de campañas sin baja', () async {
    await replica.bajar({
      'campania': [
        filaCampania('camp-1', 'Propia'),
        filaCampania('camp-2', 'De otro'),
        filaCampania('camp-3', 'Con la inscripción dada de baja'),
        filaCampania('camp-4', 'Campaña dada de baja', deBaja: true),
      ],
      'campania_colportor': [
        filaInscripcion('insc-1', campania: 'camp-1'),
        filaInscripcion('insc-2', campania: 'camp-2', usuario: 'otro'),
        filaInscripcion('insc-3', campania: 'camp-3', deBaja: true),
        filaInscripcion('insc-4', campania: 'camp-4'),
      ],
    });

    final emisiones = await escuchar();

    expect([for (final c in emisiones.single!) c.nombre], ['Propia']);
  });

  test(
    'incluye las campañas que ya terminaron: quien decide qué cuenta es la regla de fechas',
    () async {
      await replica.bajar({
        'campania': [
          filaCampania('camp-1', 'Terminada', fin: '2026-02-28'),
          filaCampania('camp-2', 'Por empezar', inicio: '2026-12-01'),
        ],
        'campania_colportor': [
          filaInscripcion('insc-1', campania: 'camp-1'),
          filaInscripcion('insc-2', campania: 'camp-2'),
        ],
      });

      final emisiones = await escuchar();

      expect([for (final c in emisiones.single!) c.nombre], ['Terminada', 'Por empezar']);
    },
  );

  test(
    'la inscripción cuya campaña todavía no llegó: null («no se sabe»), y cuando llega, la lista',
    () async {
      await replica.bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });
      final emisiones = await escuchar();
      expect(emisiones, [isNull]);

      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2027', inicio: '2026-12-01')],
      });
      await asentar();

      expect(emisiones.last!.single.nombre, 'Verano 2027');
    },
  );

  test(
    'un pull que da de baja la inscripción o cambia la fecha de inicio vuelve a emitir',
    () async {
      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2027', inicio: '2026-12-01')],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });
      final emisiones = await escuchar();

      await replica.bajar({
        'campania': [filaCampania('camp-1', 'Verano 2027', inicio: '2026-12-15')],
      });
      await asentar();
      await replica.bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', deBaja: true)],
      });
      await asentar();

      expect(emisiones.map((e) => e!.map((c) => c.fechaInicio).toList()), [
        ['2026-12-01'],
        ['2026-12-15'],
        <String>[],
      ]);
    },
  );

  test('sin la base abierta (no hay sesión) emite la lista vacía', () async {
    final sinDb = CampaniasInscriptasLocal(null);

    expect(await sinDb.observar(_usuario).first, isEmpty);
  });
}
