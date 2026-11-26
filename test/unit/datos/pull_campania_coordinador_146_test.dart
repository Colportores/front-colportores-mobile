// La lista de coordinadores de «¿Quién te acompaña?» de punta a punta (HU-JOR-003, #146), con el código
// real de los dos lados de la frontera: el motor baja `campania_coordinador` por `DriftLocalStore` y el
// aviso `out_of_area` de la 0200 (la lista completa de hoy) saca y devuelve a los coordinadores sin borrar
// nada. `jornada_acompaniante` es `push` y sube con la jornada.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/acompaniamiento_repository_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';

Map<String, Object?> _fila(String id, String usuario, String nombre, String apellido) => {
  'id': id,
  'campania_id': 'cam-1',
  'usuario_id': usuario,
  'nombre': nombre,
  'apellido': apellido,
  'created_at': '2026-11-05T15:00:00+00:00',
  'updated_at': '2026-11-05T15:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftLocalStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
  });
  tearDown(() => db.close());

  Future<void> bajar({
    Map<String, List<Map<String, Object?>>> filas = const {},
    Map<String, List<String>>? fuera,
  }) => store.applyDelta(
    filas,
    scope: 'pull',
    watermark: 'w',
    notices: PullNotices(outOfArea: fuera ?? const {}),
  );

  Future<List<String>> lista() async => [
    for (final c in await AcompaniamientoRepositoryDrift(
      db,
      encolador: EncoladorSyncEnMemoria(),
      logger: loggerMudo(),
    ).observarLista(colportorId: 'col-1').first)
      c.usuarioId,
  ];

  test('el catálogo declara campania_coordinador como pull y jornada_acompaniante como push', () {
    final coordinadores = specsDeLaApp.singleWhere((s) => s.entity == 'campania_coordinador');
    expect(coordinadores.policy, SyncPolicy.pull);
    expect(coordinadores.pullable, isTrue);
    final acompaniantes = specsDeLaApp.singleWhere((s) => s.entity == 'jornada_acompaniante');
    expect(acompaniantes.policy, SyncPolicy.push);
    expect(acompaniantes.alsoPull, isFalse);
    expect(
      specsDeLaApp.indexWhere((s) => s.entity == 'jornada_acompaniante'),
      greaterThan(specsDeLaApp.indexWhere((s) => s.entity == 'jornada')),
      reason: 'sube después de su jornada',
    );
  });

  test('lo que baja: los coordinadores de la campaña con su nombre y su apellido', () async {
    await bajar(
      filas: {
        'campania_coordinador': [
          _fila('c1', 'u-marta', 'Marta', 'Pérez'),
          _fila('c2', 'u-daniel', 'Daniel', 'Ruiz'),
        ],
      },
    );

    expect(await lista(), ['u-daniel', 'u-marta']);
  });

  test('el aviso del servidor saca al que dejó de contar sin borrar su fila', () async {
    await bajar(
      filas: {
        'campania_coordinador': [
          _fila('c1', 'u-marta', 'Marta', 'Pérez'),
          _fila('c2', 'u-daniel', 'Daniel', 'Ruiz'),
        ],
      },
    );

    await bajar(
      fuera: {
        'campania_coordinador': ['c2'],
      },
    );

    expect(await lista(), ['u-marta']);
    expect(await db.select(db.campaniaCoordinadores).get(), hasLength(2), reason: 'no se borra');
  });

  test('el coordinador que recupera el rol vuelve a la lista aunque su fila no cambie', () async {
    await bajar(
      filas: {
        'campania_coordinador': [_fila('c1', 'u-marta', 'Marta', 'Pérez')],
      },
    );
    await bajar(
      fuera: {
        'campania_coordinador': ['c1'],
      },
    );
    expect(await lista(), isEmpty);

    // El pull siguiente trae la clave vacía: nadie queda afuera. La fila no vuelve a bajar.
    await bajar(fuera: {'campania_coordinador': []});

    expect(await lista(), ['u-marta']);
  });

  test('sin la clave (un servidor de antes) no cambia nada', () async {
    await bajar(
      filas: {
        'campania_coordinador': [_fila('c1', 'u-marta', 'Marta', 'Pérez')],
      },
    );
    await bajar(
      fuera: {
        'campania_coordinador': ['c1'],
      },
    );

    await bajar();

    expect(await lista(), isEmpty);
  });

  test(
    'el aviso de las ubicaciones sigue siendo incremental: lo anterior no se desmarca',
    () async {
      await bajar(
        fuera: {
          'ubicacion': ['u1'],
        },
      );
      await bajar(
        fuera: {
          'ubicacion': ['u2'],
        },
      );

      final marcadas = await db.select(db.syncFueraDelArea).get();
      expect({for (final m in marcadas) m.filaId}, {'u1', 'u2'});
    },
  );

  test('la lista completa de una entidad no toca las marcas de otra', () async {
    await bajar(
      fuera: {
        'ubicacion': ['u1'],
        'campania_coordinador': ['c1'],
      },
    );

    await bajar(fuera: {'campania_coordinador': []});

    final marcadas = await db.select(db.syncFueraDelArea).get();
    expect([for (final m in marcadas) '${m.entidad}:${m.filaId}'], ['ubicacion:u1']);
  });

  test('lo que anota la colportora sube con la jornada, en el orden en que se anotó', () async {
    final servidor = FakeSyncTransport();
    final red = FakeConnectivityPort();
    final motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: store,
      connectivity: red,
    );
    addTearDown(() async {
      await motor.dispose();
      await red.dispose();
    });
    await sembrarJornada(db);
    final repo = AcompaniamientoRepositoryDrift(
      db,
      encolador: EncoladorSyncMotor(motor),
      logger: loggerMudo(),
    );

    await repo.guardar(
      jornadaId: 'jor-1',
      colportorId: 'col-1',
      usuarioIds: {'u-marta', 'u-daniel'},
    );
    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    final filas = servidor.rowsOf('jornada_acompaniante');
    expect({for (final f in filas) f['acompaniante_id']}, {'u-marta', 'u-daniel'});
    expect({for (final f in filas) f['jornada_id']}, {'jor-1'});
  });
}
