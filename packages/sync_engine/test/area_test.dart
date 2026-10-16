// §2.1: el pull avisa lo que salió del área (`out_of_area`) y cuándo una
// entidad arrancó de cero porque cambió el área (`area_reset`, backend 0016).
// Nada se borra del teléfono: lo que queda afuera se marca, y lo deduce el
// motor (decisión de Cristian, 02/10, backend-supabase#37).

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Devuelve las páginas en orden; una página `null` es una falla de red.
class _Guion implements SyncTransport {
  _Guion(this.paginas);

  final List<PullDelta?> paginas;
  final pedidos = <String?>[];
  final empujados = <PushBatch>[];

  @override
  Future<PushResult> push(PushBatch batch) async {
    empujados.add(batch);
    return PushResult(
      serverTime: DateTime.utc(2026, 10, 16),
      results: [
        for (final j in batch.jobs)
          JobResult(
            clientOpId: j.clientOpId,
            outcome: JobOutcome.accepted,
            syncVersion: 9,
          ),
      ],
    );
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async {
    pedidos.add(watermark);
    if (paginas.isEmpty) {
      return PullDelta(
        serverTime: DateTime.utc(2026, 10, 16),
        watermark: watermark ?? '',
        hasMore: false,
        rows: const {},
      );
    }
    final p = paginas.removeAt(0);
    if (p == null) {
      throw const TransportFailure(FailureKind.transient, message: 'sin red');
    }
    return p;
  }
}

PullDelta _pagina(
  String watermark, {
  Map<String, List<Map<String, Object?>>> rows = const {},
  bool hasMore = false,
  Map<String, List<String>> outOfArea = const {},
  Set<String> areaReset = const {},
}) => PullDelta(
  serverTime: DateTime.utc(2026, 10, 16),
  watermark: watermark,
  hasMore: hasMore,
  rows: rows,
  outOfArea: outOfArea,
  areaReset: areaReset,
);

({SyncEngine motor, InMemoryLocalStore store, InMemoryJobStore cola}) _armar(
  _Guion t,
) {
  final store = InMemoryLocalStore();
  final cola = InMemoryJobStore();
  return (
    motor: SyncEngine(
      specs: SpecRegistry(
        [SyncSpec.push('ubicacion', alsoPull: true), SyncSpec.pull('zona')],
        allEntities: {'ubicacion', 'zona'},
      ),
      transport: t,
      jobs: cola,
      store: store,
    ),
    store: store,
    cola: cola,
  );
}

Map<String, Object?> _ubi(String id) => {'id': id, 'sync_version': 1};

void main() {
  test('out_of_area marca, no borra', () async {
    final t = _Guion([
      _pagina(
        'w1',
        rows: {
          'ubicacion': [_ubi('u1'), _ubi('u2')],
        },
      ),
      _pagina(
        'w2',
        outOfArea: {
          'ubicacion': ['u1'],
        },
      ),
    ]);
    final (:motor, :store, cola: _) = _armar(t);

    await motor.syncNow();
    await motor.syncNow();

    expect(store.fueraDelArea['ubicacion'], {'u1'});
    expect(store.rows['ubicacion'], hasLength(2), reason: 'nada se borra');
    await motor.dispose();
  });

  test('una página sin filas ni watermark nuevo que solo trae avisos igual se '
      'aplica', () async {
    final t = _Guion([
      _pagina('w1'),
      _pagina(
        'w1',
        outOfArea: {
          'ubicacion': ['u9'],
        },
      ),
    ]);
    final (:motor, :store, cola: _) = _armar(t);

    await motor.syncNow();
    await motor.syncNow();

    expect(store.fueraDelArea['ubicacion'], {'u9'});
    expect(store.watermarks.values.single, 'w1');
    await motor.dispose();
  });

  test('una fila que vuelve a bajar deja de estar fuera del área', () async {
    final t = _Guion([
      _pagina(
        'w1',
        outOfArea: {
          'ubicacion': ['u1'],
        },
      ),
      _pagina(
        'w2',
        rows: {
          'ubicacion': [_ubi('u1')],
        },
      ),
    ]);
    final (:motor, :store, cola: _) = _armar(t);

    await motor.syncNow();
    await motor.syncNow();

    expect(store.fueraDelArea['ubicacion'], isEmpty);
    await motor.dispose();
  });

  group('area_reset: lo que no vuelve a bajar quedó afuera', () {
    test('en varias páginas: se decide recién en la última', () async {
      final t = _Guion([
        _pagina(
          'w1',
          rows: {
            'ubicacion': [_ubi('u1'), _ubi('u2'), _ubi('u3')],
          },
        ),
        // Le cambian la zona: la ubicación arranca de cero.
        _pagina(
          'r1',
          rows: {
            'ubicacion': [_ubi('u2')],
          },
          areaReset: {'ubicacion'},
          hasMore: true,
        ),
        _pagina(
          'r2',
          rows: {
            'ubicacion': [_ubi('u4')],
          },
        ),
      ]);
      final (:motor, :store, cola: _) = _armar(t);

      await motor.syncNow();
      await motor.syncNow();

      expect(store.fueraDelArea['ubicacion'], {'u1', 'u3'});
      await motor.dispose();
    });

    test('cortada a la mitad, se retoma y decide al terminar', () async {
      final t = _Guion([
        _pagina(
          'w1',
          rows: {
            'ubicacion': [_ubi('u1'), _ubi('u2')],
          },
        ),
        _pagina('r1', areaReset: {'ubicacion'}, hasMore: true),
        null, // se cae la red antes de la segunda página
        _pagina(
          'r2',
          rows: {
            'ubicacion': [_ubi('u2')],
          },
        ),
      ]);
      final (:motor, :store, cola: _) = _armar(t);

      await motor.syncNow();
      final cortado = await motor.syncNow();
      expect(cortado.ok, isFalse);
      expect(
        store.fueraDelArea['ubicacion'] ?? const <String>{},
        isEmpty,
        reason: 'sin la última página no se sabe qué quedó afuera',
      );

      await motor.syncNow();

      expect(t.pedidos.last, 'r1', reason: 'retoma desde la página que tenía');
      expect(store.fueraDelArea['ubicacion'], {'u1'});
      await motor.dispose();
    });
  });

  test('el pull no pisa una fila con una escritura local sin subir', () async {
    final t = _Guion([
      _pagina(
        'w1',
        rows: {
          'ubicacion': [
            {'id': 'u1', 'calle': 'del servidor', 'sync_version': 4},
            {'id': 'u2', 'calle': 'otra', 'sync_version': 1},
          ],
        },
      ),
    ]);
    final (:motor, :store, :cola) = _armar(t);
    // El push falla antes de llegar al pull: la escritura queda sin aplicar.
    await motor.stage('ubicacion', Op.update, {
      'id': 'u1',
      'calle': 'mía',
    }, syncVersion: 3);
    await cola.claimPending(limit: 10);

    await motor.syncNow();

    expect(store.rows['ubicacion']!.map((f) => f['id']), [
      'u2',
    ], reason: 'u1 tiene lo que escribió el colportor y el servidor no vio');
    await motor.dispose();
  });

  group('el cable', () {
    test('out_of_area y area_reset van y vuelven', () {
      final delta = _pagina(
        'w9',
        outOfArea: {
          'ubicacion': ['u1', 'u2'],
        },
        areaReset: {'ubicacion', 'espacio'},
      );

      final vuelta = pullResponseFromJson(pullResponseToJson(delta));

      expect(vuelta.outOfArea, {
        'ubicacion': ['u1', 'u2'],
      });
      expect(vuelta.areaReset, {'ubicacion', 'espacio'});
    });

    test('sin las claves (servidor anterior a 0016), sin avisos', () {
      final vuelta = pullResponseFromJson({
        'server_time': '2026-10-16T00:00:00Z',
        'watermark': 'w1',
        'has_more': false,
        'rows': <String, Object?>{},
      });
      expect(vuelta.outOfArea, isEmpty);
      expect(vuelta.areaReset, isEmpty);
    });
  });
}
