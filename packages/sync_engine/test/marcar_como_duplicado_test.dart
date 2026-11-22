// §6.2 del contrato (0.9.13): la unión de duplicados como trabajo del motor
// (HU-UBI-006, front-colportores-mobile#679). No es un upsert: el job es
// `{"entity": "ubicacion", "op": "marcar_como_duplicado", "payload":
// {"duplicada_id", "conservada_id"}}`, sin `sync_version`, y el servidor lo
// aplica en su lugar, después de lo que el teléfono tenía de A y de B.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _union = {'duplicada_id': 'ub-b', 'conservada_id': 'ub-a'};

SpecRegistry _registro() => SpecRegistry(
  [SyncSpec.push('ubicacion'), SyncSpec.push('espacio')],
  allEntities: {'ubicacion', 'espacio'},
);

/// Un servidor que hace lo de la 0017 y la unión de la 0069, nada más:
///
/// - una `ubicacion` viva con una calle de [ocupadas] vuelve `conflict` 23505
///   `ubicacion_direccion_unica`, sin `server_row`;
/// - lo que nombra una fila que quedó en espera **en este mismo lote** vuelve
///   `ESPERA_ALTA_EN_CONFLICTO`;
/// - la unión de una B o una A que no tiene vuelve `FILA_INEXISTENTE`.
class _Servidor implements SyncTransport {
  _Servidor({this.ocupadas = const {}});

  final Set<String> ocupadas;
  final Map<String, Map<String, Object?>> filas = {};
  final Map<String, int> versiones = {};
  final List<List<String>> lotes = [];

  @override
  Future<PushResult> push(PushBatch batch) async {
    lotes.add([for (final j in batch.jobs) j.clientOpId]);
    final enEspera = <String>{};
    final resultados = <JobResult>[];
    for (final job in batch.jobs) {
      final union = job.op == Op.marcarComoDuplicado;
      final pk =
          (union ? job.payload['duplicada_id'] : job.payload['id'])! as String;
      final nombra = {pk, ...job.payload.values.whereType<String>()};
      final espera = nombra.intersection(enEspera);
      if (espera.isNotEmpty) {
        if (!union) enEspera.add(pk);
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
      if (union) {
        final a = job.payload['conservada_id']! as String;
        if (!filas.containsKey(pk) || !filas.containsKey(a)) {
          resultados.add(
            JobResult(
              clientOpId: job.clientOpId,
              outcome: JobOutcome.invalid,
              code: 'FILA_INEXISTENTE',
            ),
          );
          continue;
        }
        filas[pk] = {...filas[pk]!, 'deleted_at': 'ahora'};
        versiones[pk] = (versiones[pk] ?? 0) + 1;
        resultados.add(
          JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.accepted,
            syncVersion: versiones[pk],
          ),
        );
        continue;
      }
      final fila = {...?filas[pk], ...job.payload};
      if (fila['deleted_at'] == null && ocupadas.contains(fila['calle'])) {
        enEspera.add(pk);
        resultados.add(
          JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.conflict,
            code: '23505',
            constraint: 'ubicacion_direccion_unica',
          ),
        );
        continue;
      }
      filas[pk] = fila;
      versiones[pk] = (versiones[pk] ?? 0) + 1;
      resultados.add(
        JobResult(
          clientOpId: job.clientOpId,
          outcome: JobOutcome.accepted,
          syncVersion: versiones[pk],
        ),
      );
    }
    return PushResult(
      serverTime: DateTime.utc(2026, 11, 10),
      results: resultados,
    );
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async => PullDelta(
    serverTime: DateTime.utc(2026, 11, 10),
    watermark: watermark ?? '0',
    hasMore: false,
    rows: const {},
  );
}

typedef _Armado = ({
  SyncEngine motor,
  InMemoryJobStore cola,
  InMemoryLocalStore local,
});

_Armado _armar(SyncTransport transport) {
  final cola = InMemoryJobStore();
  final local = InMemoryLocalStore();
  // El reloj avanza un milisegundo por lectura: cada stage tiene su instante.
  var t = DateTime.utc(2026, 11, 10, 9);
  final motor = SyncEngine(
    specs: _registro(),
    transport: transport,
    jobs: cola,
    store: local,
    clock: () => t = t.add(const Duration(milliseconds: 1)),
  );
  addTearDown(motor.dispose);
  return (motor: motor, cola: cola, local: local);
}

QueuedJob _job(InMemoryJobStore cola, String opId) =>
    cola.all.firstWhere((q) => q.job.clientOpId == opId);

void main() {
  group('el cable', () {
    test('viaja con su nombre, sin sync_version, y vuelve igual', () {
      final job = SyncJob(
        clientOpId: 'op-1',
        entity: 'ubicacion',
        op: Op.marcarComoDuplicado,
        payload: _union,
        createdAt: DateTime.utc(2026, 11, 10),
        rowPk: 'ub-b',
      );
      const sobre = ClientEnvelope(
        deviceId: '01890a5d-ac96-774b-bcce-b302099a8057',
        appVersion: '1.0.0',
      );

      final json = pushRequestToJson(PushBatch([job]), sobre);
      final [crudo as Map<String, Object?>] = json['jobs']! as List<Object?>;

      expect(crudo, {
        'client_op_id': 'op-1',
        'entity': 'ubicacion',
        'op': 'marcar_como_duplicado',
        'payload': _union,
      });
      final vuelta = pushRequestFromJson(json).batch.jobs.single;
      expect(vuelta.op, Op.marcarComoDuplicado);
      expect(vuelta.payload, _union);
      expect(vuelta.syncVersion, isNull);
    });

    test('las ops de siempre siguen con su nombre y su sync_version', () {
      final job = SyncJob(
        clientOpId: 'op-1',
        entity: 'ubicacion',
        op: Op.update,
        payload: const {'id': 'ub-b'},
        syncVersion: 3,
        createdAt: DateTime.utc(2026, 11, 10),
      );

      final [crudo as Map<String, Object?>] = jobsToJson(PushBatch([job]));

      expect(crudo['op'], 'update');
      expect(crudo['sync_version'], 3);
      expect(
        [for (final op in Op.values) op.wireName],
        ['insert', 'update', 'delete', 'marcar_como_duplicado'],
      );
    });

    test('un op desconocido es un cuerpo mal formado', () {
      expect(
        () => Op.fromWireName('marcarComoDuplicado'),
        throwsFormatException,
      );
      expect(
        () => pushRequestFromJson({
          'jobs': [
            {
              'client_op_id': 'op-1',
              'entity': 'ubicacion',
              'op': 'upsert',
              'payload': <String, Object?>{},
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('stage', () {
    test(
      'se encola aparte, con la duplicada como fila y sin versión esperada',
      () async {
        final (:motor, :cola, local: _) = _armar(FakeSyncTransport());

        await motor.stage(
          'ubicacion',
          Op.marcarComoDuplicado,
          _union,
          clientOpId: 'op-union',
          syncVersion: 4,
        );

        final q = _job(cola, 'op-union');
        expect(q.state, JobState.pending);
        expect(q.job.op, Op.marcarComoDuplicado);
        expect(q.job.rowPk, 'ub-b');
        expect(q.job.syncVersion, isNull);
        expect(q.job.payload, _union);
      },
    );

    test('sin los dos ids no se encola', () async {
      final (:motor, :cola, local: _) = _armar(FakeSyncTransport());

      await expectLater(
        motor.stage('ubicacion', Op.marcarComoDuplicado, const {
          'duplicada_id': 'ub-b',
        }),
        throwsArgumentError,
      );
      expect(cola.all, isEmpty);
    });

    test('no se funde en una escritura pendiente de B, ni una de B después en '
        'ella', () async {
      final (:motor, :cola, local: _) = _armar(FakeSyncTransport());

      await motor.stage(
        'ubicacion',
        Op.update,
        {'id': 'ub-b', 'calle': 'Rivera 2'},
        clientOpId: 'op-antes',
        syncVersion: 1,
      );
      await motor.stage(
        'ubicacion',
        Op.marcarComoDuplicado,
        _union,
        clientOpId: 'op-union',
      );
      await motor.stage(
        'ubicacion',
        Op.update,
        {'id': 'ub-b', 'calle': 'Rivera 3'},
        clientOpId: 'op-despues',
        syncVersion: 1,
      );

      expect(
        [for (final q in cola.all) q.job.clientOpId],
        ['op-antes', 'op-union', 'op-despues'],
      );
      expect(_job(cola, 'op-union').job.payload, _union);
      expect(_job(cola, 'op-antes').job.payload['calle'], 'Rivera 2');
      expect(_job(cola, 'op-despues').job.payload['calle'], 'Rivera 3');
    });
  });

  group('la subida', () {
    test('sale detrás de las altas pendientes de A y de B, y la versión de B '
        'vuelve a la fila', () async {
      final servidor = _Servidor();
      final (:motor, :cola, :local) = _armar(servidor);
      local.rows['ubicacion'] = [
        {'id': 'ub-a', 'sync_version': 0},
        {'id': 'ub-b', 'sync_version': 0},
      ];

      await motor.stage('ubicacion', Op.insert, {
        'id': 'ub-a',
      }, clientOpId: 'op-alta-a');
      await motor.stage('ubicacion', Op.insert, {
        'id': 'ub-b',
      }, clientOpId: 'op-alta-b');
      await motor.stage(
        'ubicacion',
        Op.marcarComoDuplicado,
        _union,
        clientOpId: 'op-union',
      );
      final resultado = await motor.syncNow();

      expect(resultado.invalidated, 0);
      expect(servidor.lotes.expand((l) => l), [
        'op-alta-a',
        'op-alta-b',
        'op-union',
      ]);
      expect(_job(cola, 'op-union').state, JobState.done);
      expect(servidor.filas['ub-b']!['deleted_at'], isNotNull);
      expect(
        local.rows['ubicacion']!.firstWhere((f) => f['id'] == 'ub-b'),
        {'id': 'ub-b', 'sync_version': 2},
        reason: 'la del alta (1) y después la de la unión (2)',
      );
    });

    test(
      'el alta de B que sube en el mismo ciclo no le pone versión a la unión',
      () async {
        final transport = FakeSyncTransport();
        final (:motor, :cola, local: _) = _armar(transport);
        transport.seed('ubicacion', [
          {'id': 'ub-a'},
        ]);

        await motor.stage('ubicacion', Op.insert, {'id': 'ub-b'});
        await motor.stage(
          'ubicacion',
          Op.marcarComoDuplicado,
          _union,
          clientOpId: 'op-union',
        );
        await motor.syncNow();

        final enviada = transport.batches
            .expand((b) => b.jobs)
            .firstWhere((j) => j.clientOpId == 'op-union');
        expect(enviada.syncVersion, isNull);
        expect(_job(cola, 'op-union').state, JobState.done);
      },
    );

    test(
      'con el alta de A en conflicto espera, y sale detrás de ella cuando la '
      'app la resuelve',
      () async {
        final servidor = _Servidor(ocupadas: {'Rivera 1'});
        final (:motor, :cola, local: _) = _armar(servidor);
        servidor.filas['ub-b'] = {'id': 'ub-b', 'calle': 'Rivera 1 bis'};

        await motor.stage('ubicacion', Op.insert, {
          'id': 'ub-a',
          'calle': 'Rivera 1',
        }, clientOpId: 'op-alta-a');
        await motor.syncNow();
        expect(_job(cola, 'op-alta-a').state, JobState.blocked);

        await motor.stage(
          'ubicacion',
          Op.marcarComoDuplicado,
          _union,
          clientOpId: 'op-union',
        );
        await motor.syncNow();
        final union = _job(cola, 'op-union');
        expect(union.state, JobState.waiting);
        expect(union.dependsOn, 'ub-a');
        expect(servidor.lotes.expand((l) => l), isNot(contains('op-union')));

        // Una escritura de B mientras tanto no se la lleva puesta.
        await motor.stage(
          'ubicacion',
          Op.update,
          {'id': 'ub-b', 'deleted_at': 'ya'},
          clientOpId: 'op-baja-b',
          syncVersion: 1,
        );
        expect(_job(cola, 'op-union').job.payload, _union);

        // La colportora corrige la dirección de A (vista 10).
        await motor.stage('ubicacion', Op.update, {
          'id': 'ub-a',
          'calle': 'Rivera 2',
        }, syncVersion: 0);
        final antes = servidor.lotes.length;
        await motor.syncNow();

        final despues = servidor.lotes.skip(antes).expand((l) => l).toList();
        expect(despues.indexOf('op-alta-a'), 0);
        expect(
          despues.indexOf('op-union'),
          greaterThan(despues.indexOf('op-alta-a')),
        );
        expect(_job(cola, 'op-union').state, JobState.done);
      },
    );

    test(
      'encolada mientras el alta de A espera, sin haber salido, también sale '
      'detrás de ella',
      () async {
        final servidor = _Servidor(ocupadas: {'Rivera 1'});
        final (:motor, :cola, local: _) = _armar(servidor);
        servidor.filas['ub-b'] = {'id': 'ub-b', 'calle': 'Rivera 1 bis'};

        await motor.stage('ubicacion', Op.insert, {
          'id': 'ub-a',
          'calle': 'Rivera 1',
        }, clientOpId: 'op-alta-a');
        await motor.syncNow();
        await motor.stage(
          'ubicacion',
          Op.marcarComoDuplicado,
          _union,
          clientOpId: 'op-union',
        );
        expect(_job(cola, 'op-union').state, JobState.pending);

        await motor.stage('ubicacion', Op.update, {
          'id': 'ub-a',
          'calle': 'Rivera 2',
        }, syncVersion: 0);

        final pendientes = await cola.listPending();
        expect(
          [for (final q in pendientes) q.job.clientOpId],
          ['op-alta-a', 'op-union'],
        );
        await motor.syncNow();
        expect(_job(cola, 'op-union').state, JobState.done);
        expect(servidor.filas['ub-b']!['deleted_at'], isNotNull);
      },
    );
  });

  group('las respuestas', () {
    test(
      'duplicate (B ya unida) la da por hecha, con la versión de B',
      () async {
        final transport = FakeSyncTransport();
        final (:motor, :cola, :local) = _armar(transport);
        transport.seed('ubicacion', [
          {'id': 'ub-a', 'sync_version': 1},
          {'id': 'ub-b', 'sync_version': 1},
        ]);
        local.rows['ubicacion'] = [
          {'id': 'ub-b', 'sync_version': 1},
        ];

        await motor.stage(
          'ubicacion',
          Op.marcarComoDuplicado,
          _union,
          clientOpId: 'op-1',
        );
        await motor.syncNow();
        await motor.stage(
          'ubicacion',
          Op.marcarComoDuplicado,
          _union,
          clientOpId: 'op-2',
        );
        await motor.syncNow();

        expect(_job(cola, 'op-1').state, JobState.done);
        expect(_job(cola, 'op-2').state, JobState.done);
        expect(local.rows['ubicacion']!.single['sync_version'], 2);
        expect(transport.rowsOf('ubicacion').map((f) => f['id']), ['ub-a']);
      },
    );

    for (final code in ['UB003', 'UB004']) {
      test(
        'invalid $code la deja INVALID, visible, sin tumbar el lote',
        () async {
          final transport = FakeSyncTransport();
          final (:motor, :cola, local: _) = _armar(transport);
          transport.seed('ubicacion', [
            {'id': 'ub-a'},
            {'id': 'ub-b'},
          ]);
          transport.rejectJob('op-union', code);

          await motor.stage(
            'ubicacion',
            Op.marcarComoDuplicado,
            _union,
            clientOpId: 'op-union',
          );
          await motor.stage('espacio', Op.insert, {
            'id': 'esp-1',
          }, clientOpId: 'op-espacio');
          final resultado = await motor.syncNow();

          expect(resultado.invalidated, 1);
          final q = _job(cola, 'op-union');
          expect(q.state, JobState.invalid);
          expect(q.code, code);
          expect(_job(cola, 'op-espacio').state, JobState.done);
          expect(
            [for (final f in await motor.failedOperations()) (f.op, f.code)],
            [(Op.marcarComoDuplicado, code)],
          );
        },
      );
    }

    test(
      'el servidor falso aplica la regla: A de baja es UB003 y B = A es UB004',
      () async {
        final transport = FakeSyncTransport();
        final (:motor, :cola, local: _) = _armar(transport);
        transport.seed('ubicacion', [
          {'id': 'ub-a'},
          {'id': 'ub-b'},
        ]);

        await motor.stage('ubicacion', Op.delete, {
          'id': 'ub-a',
        }, syncVersion: 1);
        await motor.stage(
          'ubicacion',
          Op.marcarComoDuplicado,
          _union,
          clientOpId: 'op-a-de-baja',
        );
        await motor.stage('ubicacion', Op.marcarComoDuplicado, const {
          'duplicada_id': 'ub-b',
          'conservada_id': 'ub-b',
        }, clientOpId: 'op-misma');
        await motor.syncNow();

        expect(_job(cola, 'op-a-de-baja').code, 'UB003');
        expect(_job(cola, 'op-misma').code, 'UB004');
      },
    );
  });
}
