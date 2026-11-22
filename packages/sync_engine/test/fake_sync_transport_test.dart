// Corre con `dart test`, en la VM, sin emulador ni red (§5.9).

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

final _serverTime = DateTime.utc(2026, 8, 28, 15, 44, 13, 849);

var _n = 0;
SyncJob _job(
  String pk, {
  Op op = Op.insert,
  int? syncVersion,
  String entity = 'venta',
  String? opId,
  Map<String, Object?> extra = const {},
}) =>
    SyncJob(
      clientOpId: opId ?? 'op-${++_n}',
      entity: entity,
      op: op,
      payload: {'id': pk, ...extra},
      syncVersion: syncVersion,
      createdAt: DateTime.utc(2026, 8, 28, 12, 0, _n),
    );

FakeSyncTransport _fake() => FakeSyncTransport(clock: () => _serverTime);

void main() {
  group('idempotencia (§5.3)', () {
    test('el mismo client_op_id dos veces se aplica una sola vez', () async {
      final t = _fake();
      final batch = PushBatch([_job('v1', opId: 'op-fijo')]);

      final primera = await t.push(batch);
      final segunda = await t.push(batch);

      expect(primera.results.single.outcome, JobOutcome.accepted);
      expect(segunda.results.single.outcome, JobOutcome.duplicate);
      expect(t.rowsOf('venta'), hasLength(1));
    });

    test('respuesta perdida: el reintento vuelve duplicate, no crea otra venta',
        () async {
      final t = _fake()..loseNextResponse();
      final batch = PushBatch([_job('v1', opId: 'op-fijo')]);

      await expectLater(
        t.push(batch),
        throwsA(isA<TransportFailure>()
            .having((f) => f.kind, 'kind', FailureKind.transient)),
      );
      expect(t.rowsOf('venta'), hasLength(1),
          reason: 'el servidor sí lo aplicó');

      final reintento = await t.push(batch);
      expect(reintento.results.single.outcome, JobOutcome.duplicate);
      expect(reintento.settled, ['op-fijo']);
      expect(t.rowsOf('venta'), hasLength(1));
    });

    test('replay de §7: insert sobre una PK que ya existe es éxito, no error',
        () async {
      final t = _fake();
      // El job original subió antes del backup y el cache de client_op_id ya
      // venció (TTL 24 h). El replay llega con otro op_id y la misma PK v7.
      await t.push(PushBatch([_job('v1', opId: 'op-original')]));
      final replay = await t.push(PushBatch([_job('v1', opId: 'op-replay')]));

      final r = replay.results.single;
      expect(r.outcome, JobOutcome.duplicate);
      expect(r.outcome, isNot(JobOutcome.invalid),
          reason: 'un replay idempotente no puede terminar en INVALID');
      expect(t.rowsOf('venta'), hasLength(1), reason: 'cero duplicados');
    });
  });

  group('clasificación de errores (§5.1)', () {
    test('transitorio deja el job en PENDING; payload lo deja en INVALID', () {
      expect(kindForStatus(500), FailureKind.transient);
      expect(kindForStatus(429), FailureKind.transient);
      expect(kindForStatus(422), FailureKind.payload);
      expect(kindForStatus(400), FailureKind.payload);
      expect(kindForStatus(403), FailureKind.payload);
      expect(kindForStatus(409), FailureKind.conflict);

      expect(FailureKind.transient.resultingState, JobState.pending);
      expect(FailureKind.payload.resultingState, JobState.invalid);
      expect(FailureKind.transient.retriable, isTrue);
      expect(FailureKind.payload.retriable, isFalse);
    });

    test('failWith(422) rebota la llamada como payload', () async {
      final t = _fake()..failWith(422, code: 'VENTA_SIN_ITEMS');
      await expectLater(
        t.push(PushBatch([_job('v1')])),
        throwsA(isA<TransportFailure>()
            .having((f) => f.kind, 'kind', FailureKind.payload)
            .having((f) => f.status, 'status', 422)
            .having((f) => f.code, 'code', 'VENTA_SIN_ITEMS')),
      );
      expect(t.rowsOf('venta'), isEmpty);
      // Se consume una sola vez: la siguiente pasa.
      await expectLater(t.push(PushBatch([_job('v1')])), completes);
    });

    test('el 429 llega con cuánto esperar y sigue siendo transitorio',
        () async {
      final t = _fake()..failWith(429, retryAfter: const Duration(seconds: 30));
      await expectLater(
        t.pull(entities: const ['producto']),
        throwsA(isA<TransportFailure>()
            .having((f) => f.kind, 'kind', FailureKind.transient)
            .having((f) => f.retryAfter, 'retryAfter',
                const Duration(seconds: 30))),
      );
    });

    test('un job inválido no tumba el resto del lote', () async {
      final t = _fake()..rejectJob('op-malo', 'PRODUCTO_INEXISTENTE', 'pk 812');
      final r = await t.push(PushBatch([
        _job('v1', opId: 'op-bueno'),
        _job('v2', opId: 'op-malo'),
        _job('v3', opId: 'op-otro'),
      ]));

      expect(
          r.byOutcome(JobOutcome.invalid).single.code, 'PRODUCTO_INEXISTENTE');
      expect(r.settled, ['op-bueno', 'op-otro']);
      expect(t.rowsOf('venta'), hasLength(2),
          reason: 'el rechazado no se aplicó');
    });

    test('offline no se consume: falla hasta que vuelve la red', () async {
      final t = _fake()..offline();
      for (var i = 0; i < 5; i++) {
        await expectLater(
            t.push(PushBatch([_job('v$i')])),
            throwsA(isA<TransportFailure>()
                .having((f) => f.kind, 'kind', FailureKind.transient)));
      }
      expect(t.rowsOf('venta'), isEmpty);
      expect(t.batches, hasLength(5), reason: 'los intentos quedan a la vista');

      t.online();
      await expectLater(t.push(PushBatch([_job('v9')])), completes);
    });
  });

  group('conflictos y LWW (§5.4)', () {
    test('sync_version vieja vuelve conflict con la fila del servidor',
        () async {
      final t = _fake();
      await t.push(PushBatch([
        _job('u1', extra: {'nombre': 'Casa azul'})
      ]));
      // Otro dispositivo ya la movió a la versión 2.
      await t.push(PushBatch([
        _job('u1',
            op: Op.update, syncVersion: 1, extra: {'nombre': 'Casa roja'})
      ]));

      // Este llega tarde, con la versión 1 en la mano.
      final tarde = await t.push(PushBatch([
        _job('u1',
            op: Op.update, syncVersion: 1, extra: {'nombre': 'Casa verde'})
      ]));

      final r = tarde.results.single;
      expect(r.outcome, JobOutcome.conflict);
      expect(r.syncVersion, 2);
      expect(r.serverRow!['nombre'], 'Casa roja',
          reason: 'el motor resuelve el LWW sin un pull extra');
      expect(r.outcome, isNot(JobOutcome.invalid),
          reason: 'un conflicto no manda el job a la cola de error');
    });

    test('el update con la versión correcta avanza a la siguiente', () async {
      final t = _fake();
      await t.push(PushBatch([_job('u1')]));
      final r =
          await t.push(PushBatch([_job('u1', op: Op.update, syncVersion: 1)]));
      expect(r.results.single.outcome, JobOutcome.accepted);
      expect(r.results.single.syncVersion, 2);
    });
  });

  group('pull y watermark', () {
    test('trae solo lo posterior al watermark y avisa con hasMore', () async {
      final t = _fake()
        ..seed('producto', [
          {'id': 'p1', 'nombre': 'El Camino a Cristo'},
          {'id': 'p2', 'nombre': 'El Deseado'},
        ]);

      final primera = await t.pull(entities: const ['producto'], limit: 1);
      expect(primera.rows['producto']!.single['id'], 'p1');
      expect(primera.hasMore, isTrue);

      final segunda = await t.pull(
          entities: const ['producto'], watermark: primera.watermark, limit: 1);
      expect(segunda.rows['producto']!.single['id'], 'p2');
      expect(segunda.hasMore, isFalse);
    });

    test('si el watermark no avanza, el próximo pull trae lo mismo', () async {
      final t = _fake()
        ..seed('producto', [
          {'id': 'p1'},
          {'id': 'p2'},
        ]);

      final primera = await t.pull(entities: const ['producto'], limit: 1);
      // Aplicar la transacción local falló: el watermark NO se guarda.
      final reintento = await t.pull(entities: const ['producto'], limit: 1);

      expect(reintento.rows['producto']!.single['id'], 'p1');
      expect(reintento.watermark, primera.watermark);
      expect(t.pulls.map((p) => p.watermark), [null, null]);
    });

    test('sin novedades devuelve el watermark igual y ninguna entidad',
        () async {
      final t = _fake();
      final r = await t.pull(entities: const ['producto'], watermark: 'w-7');
      expect(r.rows, isEmpty);
      expect(r.watermark, 'w-7');
      expect(r.hasMore, isFalse);
    });

    test('una entidad sin cambios queda ausente, no vacía', () async {
      final t = _fake()
        ..seed('producto', [
          {'id': 'p1'}
        ]);
      final r = await t.pull(entities: const ['producto', 'campania']);
      expect(r.rows.keys, ['producto']);
      expect(r.rows.containsKey('campania'), isFalse,
          reason: 'el motor no borra nada por ausencia');
    });
  });

  test('el server_time no depende del reloj del dispositivo', () async {
    final r = await _fake().push(PushBatch([_job('v1')]));
    expect(r.serverTime, _serverTime);
    expect(r.serverTime.isUtc, isTrue);
  });

  test('el tamaño del lote se puede medir contra el tope de ~1 MB (§5.5)', () {
    final chico = PushBatch([_job('v1')]);
    final grande = PushBatch([for (var i = 0; i < 50; i++) _job('v$i')]);
    expect(estimatedBytes(chico), lessThan(estimatedBytes(grande)));
    expect(estimatedBytes(grande), lessThan(1024 * 1024));
  });
}
