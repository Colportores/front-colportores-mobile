// §5.4: el servidor compara la `sync_version` esperada por igualdad. La que le
// da a una fila al aplicar su escritura tiene que volver al teléfono —a la fila
// y a lo que de ella espera en la cola—, o el próximo update vuelve `conflict`
// y el LWW pisa la edición con la fila vieja.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

({
  SyncEngine motor,
  FakeSyncTransport servidor,
  InMemoryJobStore cola,
  InMemoryLocalStore filas,
})
_armar() {
  final servidor = FakeSyncTransport();
  final cola = InMemoryJobStore();
  final filas = InMemoryLocalStore();
  final motor = SyncEngine(
    specs: SpecRegistry(
      [
        SyncSpec.push('jornada', critical: true),
        SyncSpec.push('house_status', pk: 'ubicacion_id'),
      ],
      allEntities: {'jornada', 'house_status'},
    ),
    transport: servidor,
    jobs: cola,
    store: filas,
  );
  return (motor: motor, servidor: servidor, cola: cola, filas: filas);
}

void main() {
  test('cerrar una jornada que ya subió no la reabre: el update espera la '
      'versión que dio el servidor', () async {
    final (:motor, :servidor, :cola, :filas) = _armar();
    // La fila local, como la escribe la app al iniciar la jornada.
    filas.rows['jornada'] = [
      {'id': 'j-1', 'fin': null, 'sync_version': 0},
    ];
    await motor.stage('jornada', Op.insert, {
      'id': 'j-1',
      'fin': null,
      'sync_version': 0,
    });
    await motor.syncNow();

    expect(
      filas.rows['jornada']!.single['sync_version'],
      1,
      reason: 'la versión del alta volvió a la fila',
    );

    // Al cerrarla, la app stagea con la versión que ve en la fila.
    final version = filas.rows['jornada']!.single['sync_version']! as int;
    await motor.stage('jornada', Op.update, {
      'id': 'j-1',
      'fin': '2026-10-16T20:00:00Z',
      'sync_version': version,
    }, syncVersion: version);
    final resultado = await motor.syncNow();

    expect(resultado.conflicts, 0);
    expect(servidor.rowsOf('jornada').single['fin'], '2026-10-16T20:00:00Z');
    expect(filas.rows['jornada']!.single['sync_version'], 2);
    expect((await cola.status()).pending, 0);
    await motor.dispose();
  });

  test('un update que se encoló mientras el anterior viajaba recibe la '
      'versión nueva antes de salir', () async {
    final (:motor, :servidor, :cola, :filas) = _armar();
    servidor.seed('jornada', [
      {'id': 'j-1', 'fin': null, 'sync_version': 1},
    ]);
    filas.rows['jornada'] = [
      {'id': 'j-1', 'fin': null, 'sync_version': 1},
    ];
    await motor.stage('jornada', Op.update, {
      'id': 'j-1',
      'total_visitas': 3,
    }, syncVersion: 1);
    // Tomado para el lote: ya no se le puede fundir nada.
    final [enVuelo] = await cola.claimPending(limit: 1);
    await cola.markPending([enVuelo.id]);
    await cola.claimPending(limit: 1);
    final otro = await motor.stage('jornada', Op.update, {
      'id': 'j-1',
      'total_visitas': 4,
    }, syncVersion: 1);
    await cola.markPending([enVuelo.id]);

    await motor.syncNow();

    expect(
      cola.byId(otro).state,
      JobState.done,
      reason: 'si hubiera viajado esperando la 1, volvía conflict',
    );
    expect(servidor.rowsOf('jornada').single['total_visitas'], 4);
    await motor.dispose();
  });

  test('dos updates sin mandar de la misma fila se funden en uno', () async {
    final (:motor, :servidor, :cola, :filas) = _armar();
    servidor.seed('jornada', [
      {'id': 'j-1', 'total_visitas': 0, 'sync_version': 1},
    ]);

    final a = await motor.stage('jornada', Op.update, {
      'id': 'j-1',
      'total_visitas': 1,
    }, syncVersion: 1);
    final b = await motor.stage('jornada', Op.update, {
      'id': 'j-1',
      'total_ventas': 2,
    }, syncVersion: 1);

    expect(b, a, reason: 'el segundo se fundió en el primero');
    expect(cola.byId(a).job.payload, {
      'id': 'j-1',
      'total_visitas': 1,
      'total_ventas': 2,
    });
    await motor.syncNow();
    expect(servidor.rowsOf('jornada').single, containsPair('total_ventas', 2));
    await motor.dispose();
  });

  test(
    'un alta sin mandar absorbe sus updates y sigue siendo un alta',
    () async {
      final (:motor, :servidor, :cola, :filas) = _armar();

      final alta = await motor.stage('jornada', Op.insert, {
        'id': 'j-1',
        'fin': null,
      });
      await motor.stage('jornada', Op.update, {
        'id': 'j-1',
        'fin': '2026-10-16T20:00:00Z',
      }, syncVersion: 0);

      expect(cola.all, hasLength(1));
      expect(cola.byId(alta).job.op, Op.insert);
      expect(cola.byId(alta).job.syncVersion, isNull);
      await motor.syncNow();
      expect(servidor.rowsOf('jornada').single['fin'], '2026-10-16T20:00:00Z');
      await motor.dispose();
    },
  );

  test('un delete no se funde: sale después de lo que había', () async {
    final (:motor, :servidor, :cola, :filas) = _armar();
    await motor.stage('jornada', Op.insert, {'id': 'j-1'});
    await motor.stage('jornada', Op.delete, {'id': 'j-1'}, syncVersion: 0);

    expect(cola.all, hasLength(2));
    await motor.dispose();
  });

  test('la PK es la de la SyncSpec: house_status usa ubicacion_id', () async {
    final (:motor, :servidor, :cola, :filas) = _armar();
    final primero = await motor.stage('house_status', Op.insert, {
      'ubicacion_id': 'u-1',
      'estado': 'NO_VISITADA',
    });
    final segundo = await motor.stage('house_status', Op.update, {
      'ubicacion_id': 'u-1',
      'estado': 'VISITADA',
    }, syncVersion: 0);

    expect(segundo, primero);
    expect(cola.byId(primero).job.rowPk, 'u-1');
    await motor.dispose();
  });

  test(
    'la versión vuelve una vez por entidad y por lote, no por fila',
    () async {
      final servidor = FakeSyncTransport();
      final filas = _FilasQueCuentan();
      final motor = SyncEngine(
        specs: SpecRegistry([SyncSpec.push('visita')], allEntities: {'visita'}),
        transport: servidor,
        jobs: InMemoryJobStore(),
        store: filas,
      );
      for (var i = 0; i < 300; i++) {
        await motor.stage('visita', Op.insert, {'id': 'v-$i'});
      }
      await motor.syncNow();

      expect(filas.llamadas, 1);
      expect(filas.filas, 300);
      await motor.dispose();
    },
  );
}

class _FilasQueCuentan extends InMemoryLocalStore {
  int llamadas = 0;
  int filas = 0;

  @override
  Future<void> applyVersions(
    String entity, {
    required String pkColumn,
    required Map<String, int> versionPorFila,
  }) async {
    llamadas++;
    filas += versionPorFila.length;
  }
}
