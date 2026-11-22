// El motor contra un servidor que se porta mal.
//
// `has_more` viene del BFF. Si el BFF tiene un bug y lo deja en true sin
// avanzar el watermark, el cliente que confía se queda pidiendo la misma página
// para siempre: la app congelada y el plan de datos del colportor consumido.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta'),
      SyncSpec.pull('producto'),
    ], allEntities: {
      'venta',
      'producto'
    });

/// Siempre dice que hay más, y nunca avanza el watermark.
class TransporteMentiroso implements SyncTransport {
  int pulls = 0;

  @override
  Future<PushResult> push(PushBatch batch) async =>
      PushResult(serverTime: DateTime.utc(2026), results: const []);

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async {
    pulls++;
    return PullDelta(
      serverTime: DateTime.utc(2026),
      watermark: watermark ?? '',
      hasMore: true,
      rows: const {},
    );
  }
}

void main() {
  test('un has_more que nunca termina no cuelga la app', () async {
    final mentiroso = TransporteMentiroso();
    final motor = SyncEngine(
      specs: _registro(),
      transport: mentiroso,
      jobs: InMemoryJobStore(),
      store: InMemoryLocalStore(),
    );

    await motor.syncNow();

    expect(mentiroso.pulls, lessThan(5),
        reason: 'si el watermark no avanza y no vienen filas, seguir pidiendo '
            'es quemarle los datos al colportor');
    await motor.dispose();
  }, timeout: const Timeout(Duration(seconds: 10)));

  group('recover() interrumpido', _recuperacionInterrumpida);
}

// ---------------------------------------------------------------------------
// recover() interrumpido: el wizard reintenta y no puede empeorar las cosas.
// ---------------------------------------------------------------------------

void _recuperacionInterrumpida() {
  final backupDate = DateTime.utc(2026, 11, 10, 20);

  test('un corte de red a mitad de la reconciliación se puede reintentar',
      () async {
    final store = InMemoryLocalStore();
    final transport = FakeSyncTransport();
    final drive = FakeArchive(authorized: true, clock: () => backupDate);
    final snap = FakeSnapshot(
      onRestore: (restaurado) {
        for (final tabla in ['persona']) {
          final filas = restaurado[tabla] as List?;
          if (filas != null) {
            (store.rows[tabla] ??= [])
                .addAll(filas.cast<Map<String, Object?>>());
          }
        }
      },
    )..state = {
        'persona': [
          {'id': 'per-1', 'nombre': 'Ana Gómez'},
        ],
      };

    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: store,
      backup: BackupService(
        archive: drive,
        crypto: FakeCrypto(),
        snapshot: snap,
        clock: () => backupDate,
      ),
    );

    await BackupService(
      archive: drive,
      crypto: FakeCrypto(),
      snapshot: snap,
      clock: () => backupDate,
    ).backupNow(watermark: 'w-0');

    transport.seed('venta', [
      {'id': 'v-1'},
    ]);

    // Primer intento: la red se corta en la reconciliación (fase 3).
    transport.failTransient();
    await expectLater(motor.recover(), throwsA(isA<TransportFailure>()));

    // El wizard muestra el error y el colportor toca "reintentar".
    final reporte = await motor.recover();

    expect(reporte.hadBackup, isTrue);
    expect(store.rows['persona'], hasLength(1),
        reason: 'restaurar dos veces no puede duplicar la PII del colportor');
    expect(store.rows['venta'], hasLength(1),
        reason: 'ni la reconciliación duplicar sus ventas');

    await motor.dispose();
  });
}
