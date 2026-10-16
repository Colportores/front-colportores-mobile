// §2.2 del contrato: el alta que choca con la dirección única (D1) y lo que
// cuelga de ella. El servidor no guarda nada de eso y la colportora lo resuelve
// en la vista 10; el motor tiene que retenerlo sin perderlo, y soltarlo todo
// junto —en el mismo lote, con el alta primero— cuando la app reescribe la fila.

import 'dart:convert';

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Un servidor que hace lo de la 0017, nada más:
///
/// - una `ubicacion` viva con una calle de [ocupadas] vuelve `conflict` 23505
///   `ubicacion_direccion_unica`, sin `server_row`;
/// - lo que nombra (como PK o en cualquier columna) una fila que quedó en
///   espera **en este mismo lote** vuelve `ESPERA_ALTA_EN_CONFLICTO`;
/// - una columna `*_id` que nombra una fila que no tiene vuelve `invalid`
///   23503, como la FK.
class _Servidor implements SyncTransport {
  _Servidor({this.ocupadas = const {}});

  final Set<String> ocupadas;
  final Map<String, Map<String, Object?>> filas = {};
  final List<List<String>> lotes = [];

  @override
  Future<PushResult> push(PushBatch batch) async {
    lotes.add([for (final j in batch.jobs) j.clientOpId]);
    final enEspera = <String>{};
    final resultados = <JobResult>[];
    for (final job in batch.jobs) {
      final pk = job.payload['id']! as String;
      final nombra = {pk, ...job.payload.values.whereType<String>()};
      final espera = nombra.intersection(enEspera);
      if (espera.isNotEmpty) {
        enEspera.add(pk);
        resultados.add(
          JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.conflict,
            code: kCodigoEsperaAltaEnConflicto,
            dependsOn: espera.first,
          ),
        );
        continue;
      }
      final faltante = job.payload.entries.any(
        (e) =>
            e.key.endsWith('_id') &&
            e.value is String &&
            !filas.containsKey(e.value),
      );
      if (faltante) {
        resultados.add(
          JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.invalid,
            code: '23503',
          ),
        );
        continue;
      }
      final fila = {...?filas[pk], ...job.payload};
      if (job.entity == 'ubicacion' &&
          fila['deleted_at'] == null &&
          ocupadas.contains(fila['calle'])) {
        enEspera.add(pk);
        resultados.add(
          JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.conflict,
            code: '23505',
            constraint: 'ubicacion_direccion_unica',
            message: 'Ya hay otra ubicación en ${fila['calle']}',
          ),
        );
        continue;
      }
      filas[pk] = fila;
      resultados.add(
        JobResult(clientOpId: job.clientOpId, outcome: JobOutcome.accepted),
      );
    }
    return PushResult(
      serverTime: DateTime.utc(2026, 10, 16),
      results: resultados,
    );
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async => PullDelta(
    serverTime: DateTime.utc(2026, 10, 16),
    watermark: watermark ?? '0',
    hasMore: false,
    rows: const {},
  );
}

({SyncEngine motor, _Servidor servidor, InMemoryJobStore cola}) _armar({
  Set<String> ocupadas = const {'Rivera 1'},
}) {
  final servidor = _Servidor(ocupadas: ocupadas);
  final cola = InMemoryJobStore();
  // El reloj avanza un milisegundo por lectura: cada stage tiene su instante,
  // como en el teléfono.
  var t = DateTime.utc(2026, 10, 16, 9);
  final motor = SyncEngine(
    specs: SpecRegistry(
      [
        SyncSpec.push('ubicacion'),
        SyncSpec.push('espacio'),
        SyncSpec.push('venta', critical: true),
        SyncSpec.push('ubicacion_par_decidido'),
      ],
      allEntities: {'ubicacion', 'espacio', 'venta', 'ubicacion_par_decidido'},
    ),
    transport: servidor,
    jobs: cola,
    store: InMemoryLocalStore(),
    clock: () => t = t.add(const Duration(milliseconds: 1)),
  );
  return (motor: motor, servidor: servidor, cola: cola);
}

/// A, ya en el servidor, y B, el alta que choca con ella.
Future<void> _altaEnConflicto(SyncEngine motor, _Servidor servidor) async {
  servidor.filas['ubi-a'] = {'id': 'ubi-a', 'calle': 'Rivera 1'};
  await motor.stage('ubicacion', Op.insert, {
    'id': 'ubi-b',
    'calle': 'Rivera 1',
  }, clientOpId: 'op-alta-b');
  await motor.stage('espacio', Op.insert, {
    'id': 'esp-b',
    'ubicacion_id': 'ubi-b',
  }, clientOpId: 'op-espacio-b');
  await motor.syncNow();
}

JobState _estado(InMemoryJobStore cola, String opId) =>
    cola.all.firstWhere((q) => q.job.clientOpId == opId).state;

void main() {
  test(
    'el alta que choca queda BLOCKED y lo que cuelga, WAITING: nada DONE',
    () async {
      final (:motor, :servidor, :cola) = _armar();
      await _altaEnConflicto(motor, servidor);

      expect(_estado(cola, 'op-alta-b'), JobState.blocked);
      expect(_estado(cola, 'op-espacio-b'), JobState.waiting);

      final enEspera = await motor.heldQueue();
      expect(
        [for (final q in enEspera) q.job.clientOpId],
        ['op-alta-b', 'op-espacio-b'],
      );
      expect(
        enEspera.first.code,
        '23505',
        reason: 'la app elige la vista 10 por el code',
      );
      expect(enEspera.last.dependsOn, 'ubi-b');

      final s = await cola.status();
      expect((s.blocked, s.waiting, s.pending, s.invalid), (1, 1, 0, 0));
      expect(servidor.filas.keys, [
        'ubi-a',
      ], reason: 'el servidor no guardó nada');
      await motor.dispose();
    },
  );

  test('un ciclo más no lo reintenta: espera a la colportora', () async {
    final (:motor, :servidor, :cola) = _armar();
    await _altaEnConflicto(motor, servidor);
    final antes = servidor.lotes.length;

    await motor.syncNow();

    expect(servidor.lotes, hasLength(antes));
    expect(_estado(cola, 'op-alta-b'), JobState.blocked);
    await motor.dispose();
  });

  test(
    'lo que nombra la fila bloqueada y se encola después no sale: WAITING',
    () async {
      final (:motor, :servidor, :cola) = _armar();
      await _altaEnConflicto(motor, servidor);

      // Una venta en la casa en conflicto, cargada una hora después. Si saliera
      // sola, el servidor no tendría el alta en ese lote y la devolvería INVALID.
      await motor.stage('venta', Op.insert, {
        'id': 'v-1',
        'ubicacion_id': 'ubi-b',
      }, clientOpId: 'op-venta');
      await motor.syncNow();

      expect(servidor.lotes.expand((l) => l), isNot(contains('op-venta')));
      final venta = cola.all.firstWhere((q) => q.job.clientOpId == 'op-venta');
      expect(venta.state, JobState.waiting);
      expect(venta.dependsOn, 'ubi-b');
      await motor.dispose();
    },
  );

  test('en cascada: lo que nombra algo que espera, también espera', () async {
    final (:motor, :servidor, :cola) = _armar();
    await _altaEnConflicto(motor, servidor);

    await motor.stage('venta', Op.insert, {
      'id': 'v-1',
      'espacio_id': 'esp-b',
    }, clientOpId: 'op-venta');
    await motor.syncNow();

    expect(_estado(cola, 'op-venta'), JobState.waiting);
    await motor.dispose();
  });

  group('cambiar la dirección (vista 10)', () {
    test('el update reemplaza el alta en espera, sin un job más', () async {
      final (:motor, :servidor, :cola) = _armar();
      await _altaEnConflicto(motor, servidor);
      final jobs = cola.all.length;

      final id = await motor.stage('ubicacion', Op.update, {
        'id': 'ubi-b',
        'calle': 'Rivera 3',
      });

      expect(cola.all, hasLength(jobs));
      final alta = cola.byId(id);
      expect(alta.job.clientOpId, 'op-alta-b');
      expect(
        alta.job.op,
        Op.insert,
        reason: 'el servidor no tiene la fila: sigue siendo un alta',
      );
      expect(alta.job.payload, {'id': 'ubi-b', 'calle': 'Rivera 3'});
      expect(alta.state, JobState.pending);
      expect(alta.code, isEmpty);
      await motor.dispose();
    });

    test(
      'el alta y lo que cuelga suben juntos, en el mismo lote y en orden',
      () async {
        final (:motor, :servidor, :cola) = _armar();
        await _altaEnConflicto(motor, servidor);

        await motor.stage('ubicacion', Op.update, {
          'id': 'ubi-b',
          'calle': 'Rivera 3',
        });
        await motor.syncNow();

        expect(servidor.lotes.last, ['op-alta-b', 'op-espacio-b']);
        expect(_estado(cola, 'op-alta-b'), JobState.done);
        expect(_estado(cola, 'op-espacio-b'), JobState.done);
        expect(servidor.filas['ubi-b']!['calle'], 'Rivera 3');
        expect(servidor.filas['esp-b']!['ubicacion_id'], 'ubi-b');
        await motor.dispose();
      },
    );

    test(
      'van detrás de lo que la app encoló para resolver el conflicto',
      () async {
        final (:motor, :servidor, :cola) = _armar();
        await _altaEnConflicto(motor, servidor);

        await motor.stage('ubicacion_par_decidido', Op.insert, {
          'id': 'par-1',
          'ubicacion_a_id': 'ubi-a',
          'decision': 'CONSERVAR_AMBOS',
        }, clientOpId: 'op-par');
        await motor.stage('ubicacion', Op.update, {
          'id': 'ubi-b',
          'calle': 'Rivera 3',
        });
        await motor.syncNow();

        expect(servidor.lotes.last, ['op-par', 'op-alta-b', 'op-espacio-b']);
        await motor.dispose();
      },
    );

    test(
      'un update solo de algunas columnas no borra las demás del alta',
      () async {
        final (:motor, :servidor, :cola) = _armar();
        servidor.filas['ubi-a'] = {'id': 'ubi-a', 'calle': 'Rivera 1'};
        await motor.stage('ubicacion', Op.insert, {
          'id': 'ubi-b',
          'calle': 'Rivera 1',
          'tipo': 'CASA',
        }, clientOpId: 'op-alta-b');
        await motor.syncNow();

        await motor.stage('ubicacion', Op.update, {
          'id': 'ubi-b',
          'calle': 'Rivera 3',
        });
        await motor.syncNow();

        expect(servidor.filas['ubi-b'], {
          'id': 'ubi-b',
          'calle': 'Rivera 3',
          'tipo': 'CASA',
        });
        await motor.dispose();
      },
    );

    test('un update viejo que esperaba la misma fila se funde antes, '
        'y no pisa la corrección', () async {
      final (:motor, :servidor, :cola) = _armar();
      servidor.filas['ubi-a'] = {'id': 'ubi-a', 'calle': 'Rivera 1'};
      // El alta y una corrección del número, en el mismo lote: el servidor
      // bloquea el alta y deja la corrección esperándola.
      await motor.stage('ubicacion', Op.insert, {
        'id': 'ubi-b',
        'calle': 'Rivera 1',
        'numero': '1',
      }, clientOpId: 'op-alta-b');
      await motor.stage('ubicacion', Op.update, {
        'id': 'ubi-b',
        'calle': 'Rivera 1',
        'numero': '2',
      }, clientOpId: 'op-numero');
      await motor.syncNow();
      expect(_estado(cola, 'op-numero'), JobState.waiting);

      await motor.stage('ubicacion', Op.update, {
        'id': 'ubi-b',
        'calle': 'Rivera 3',
      });
      await motor.syncNow();

      expect(servidor.filas['ubi-b'], {
        'id': 'ubi-b',
        'calle': 'Rivera 3',
        'numero': '2',
      });
      expect(
        cola.all.where((q) => q.job.clientOpId == 'op-numero'),
        isEmpty,
        reason: 'quedó fundido en el alta: mandarlo después la pisaría',
      );
      await motor.dispose();
    });

    test(
      'si vuelve a chocar, vuelve a quedar en espera, sin perder nada',
      () async {
        final (:motor, :servidor, :cola) = _armar(
          ocupadas: {'Rivera 1', 'Rivera 3'},
        );
        await _altaEnConflicto(motor, servidor);

        await motor.stage('ubicacion', Op.update, {
          'id': 'ubi-b',
          'calle': 'Rivera 3',
        });
        await motor.syncNow();

        expect(_estado(cola, 'op-alta-b'), JobState.blocked);
        expect(_estado(cola, 'op-espacio-b'), JobState.waiting);
        await motor.dispose();
      },
    );
  });

  group('unir con la otra (vista 10, «Conservar A y unir»)', () {
    test(
      'reapuntar lo que colgaba lo suelta; la baja de B no sube nada',
      () async {
        final (:motor, :servidor, :cola) = _armar();
        await _altaEnConflicto(motor, servidor);
        final antes = servidor.lotes.length;

        // La unión local: el espacio pasa a A y B se da de baja.
        await motor.stage('espacio', Op.update, {
          'id': 'esp-b',
          'ubicacion_id': 'ubi-a',
        });
        await motor.stage('ubicacion', Op.update, {
          'id': 'ubi-b',
          'calle': 'Rivera 1',
          'deleted_at': '2026-10-16T12:00:00Z',
        });
        await motor.syncNow();

        expect(
          cola.all.where((q) => q.job.clientOpId == 'op-alta-b'),
          isEmpty,
          reason: 'el servidor nunca tuvo a B: no hay nada que avisarle',
        );
        expect(
          servidor.lotes.skip(antes).expand((l) => l),
          isNot(contains('op-alta-b')),
        );
        expect(_estado(cola, 'op-espacio-b'), JobState.done);
        expect(servidor.filas['esp-b']!['ubicacion_id'], 'ubi-a');
        expect(await motor.heldQueue(), isEmpty);
        await motor.dispose();
      },
    );

    test('lo que todavía nombra a B después de la baja sale y queda INVALID, '
        'visible', () async {
      final (:motor, :servidor, :cola) = _armar();
      await _altaEnConflicto(motor, servidor);

      await motor.stage('ubicacion', Op.delete, {'id': 'ubi-b'});
      await motor.syncNow();

      expect(_estado(cola, 'op-espacio-b'), JobState.invalid);
      expect(
        await motor.heldQueue(),
        isEmpty,
        reason: 'nada espera para siempre una fila que ya no existe',
      );
      await motor.dispose();
    });
  });

  test(
    'un lote partido por tamaño no deja salir lo que cuelga sin el alta',
    () async {
      final (:motor, :servidor, :cola) = _armar();
      servidor.filas['ubi-a'] = {'id': 'ubi-a', 'calle': 'Rivera 1'};
      // Dos jobs de ~600 KB: no entran juntos en 1 MB y salen en dos lotes.
      final relleno = 'x' * (600 * 1024);
      await motor.stage('ubicacion', Op.insert, {
        'id': 'ubi-b',
        'calle': 'Rivera 1',
        'nota': relleno,
      }, clientOpId: 'op-alta-b');
      await motor.stage('espacio', Op.insert, {
        'id': 'esp-b',
        'ubicacion_id': 'ubi-b',
        'nota': relleno,
      }, clientOpId: 'op-espacio-b');
      expect(utf8.encode(relleno).length * 2, greaterThan(kMaxBatchBytes));

      await motor.syncNow();

      expect(
        servidor.lotes,
        [
          ['op-alta-b'],
        ],
        reason: 'el segundo lote se retuvo entero: sin el alta, sería INVALID',
      );
      expect(_estado(cola, 'op-espacio-b'), JobState.waiting);
      await motor.dispose();
    },
  );

  test(
    'una espera sin depends_on queda BLOCKED: si no, nada la soltaría',
    () async {
      final cola = InMemoryJobStore();
      final motor = SyncEngine(
        specs: SpecRegistry([SyncSpec.push('venta')], allEntities: {'venta'}),
        transport: _SinDependsOn(),
        jobs: cola,
        store: InMemoryLocalStore(),
      );
      await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-1');
      await motor.syncNow();

      expect(_estado(cola, 'op-1'), JobState.blocked);
      await motor.dispose();
    },
  );

  test('status cuenta lo que está en espera', () async {
    final (:motor, :servidor, :cola) = _armar();
    final estados = <SyncStatus>[];
    final sub = motor.status.listen(estados.add);
    await _altaEnConflicto(motor, servidor);
    await motor.stage('ubicacion', Op.update, {
      'id': 'ubi-b',
      'calle': 'Rivera 3',
    });
    await Future<void>.delayed(Duration.zero);

    expect(
      estados.map((s) => (s.blocked, s.waiting)),
      containsAllInOrder([(1, 1), (0, 0)]),
    );
    await sub.cancel();
    await motor.dispose();
  });
}

class _SinDependsOn implements SyncTransport {
  @override
  Future<PushResult> push(PushBatch batch) async => PushResult(
    serverTime: DateTime.utc(2026, 10, 16),
    results: [
      for (final j in batch.jobs)
        JobResult(
          clientOpId: j.clientOpId,
          outcome: JobOutcome.conflict,
          code: kCodigoEsperaAltaEnConflicto,
        ),
    ],
  );

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async => throw UnimplementedError();
}
