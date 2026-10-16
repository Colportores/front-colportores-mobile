// La cola del motor sobre la DB local tiene que portarse como la cola en memoria contra la que se
// verificó el motor entero: `runJobStoreContract` es la definición ejecutable del puerto.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/port_contracts.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final abiertas = <AppDatabase>[];
  tearDown(() async {
    for (final db in abiertas) {
      await db.close();
    }
    abiertas.clear();
  });

  DriftJobStore crear() {
    final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    abiertas.add(db);
    return DriftJobStore(db);
  }

  runJobStoreContract('DriftJobStore', crear);

  test('append entra en la transacción de la app: si la escritura de negocio falla, el job no '
      'queda', () async {
    final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    abiertas.add(db);
    final cola = DriftJobStore(db);

    await expectLater(
      db.transaction(() async {
        await cola.append(
          SyncJob(
            clientOpId: 'op-1',
            entity: 'ubicacion',
            op: Op.insert,
            payload: const {'id': 'u-1'},
            createdAt: DateTime.utc(2026, 10, 16),
            rowPk: 'u-1',
          ),
        );
        throw StateError('falló el insert de la ubicación');
      }),
      throwsStateError,
    );

    expect((await cola.status()).pending, 0, reason: 'una venta encolada sin su fila es peor');
  });

  test('el payload vuelve igual: tipos, anidados y acentos', () async {
    final cola = crear();
    const payload = {
      'id': 'u-1',
      'calle': 'Av. Ñandú',
      'lat': -34.9012345,
      'numero': null,
      'activo': true,
      'poligono': {
        'type': 'Point',
        'coordinates': [-56.1, -34.9],
      },
    };
    await cola.append(
      SyncJob(
        clientOpId: 'op-1',
        entity: 'ubicacion',
        op: Op.insert,
        payload: payload,
        createdAt: DateTime.utc(2026, 10, 16),
      ),
    );

    final [tomado] = await cola.claimPending(limit: 1);
    expect(tomado.job.payload, payload);
  });
}
