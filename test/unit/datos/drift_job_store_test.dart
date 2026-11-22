// La cola del motor sobre la DB local tiene que portarse como la cola en memoria contra la que se
// verificó el motor entero: `runJobStoreContract` es la definición ejecutable del puerto.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/uniones_locales_table.dart';
import 'package:colportores_mobile/features/mapa/data/models/movimientos_de_union.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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

  group('withUnapplied: los espacios que movió una unión sin subir (HU-UBI-006, #714)', () {
    late AppDatabase db;
    late DriftJobStore cola;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      abiertas.add(db);
      cola = DriftJobStore(db);
    });

    /// Una unión de B en A, con su trabajo «marcar como duplicado» en la cola: pasó `esp-pasado` y
    /// fundió `esp-fundido` en el único de A.
    Future<String> unir({String estado = EstadoUnionLocal.aplicada}) async {
      final trabajoId = await cola.append(
        SyncJob(
          clientOpId: 'op-union',
          entity: 'ubicacion',
          op: Op.marcarComoDuplicado,
          payload: const {'duplicada_id': 'ub-b', 'conservada_id': 'ub-a'},
          createdAt: DateTime.utc(2026, 11, 12),
          rowPk: 'ub-b',
        ),
      );
      await db
          .into(db.unionesLocales)
          .insert(
            UnionesLocalesCompanion.insert(
              trabajoId: trabajoId,
              conservadaId: 'ub-a',
              duplicadaId: 'ub-b',
              unidaEn: DateTime.utc(2026, 11, 12),
              estado: Value(estado),
              movimientos: const MovimientosDeUnion(
                espaciosPasados: ['esp-pasado'],
                espaciosFundidos: [
                  EspacioFundido(espacioId: 'esp-fundido', unicoDeA: 'esp-unico-a'),
                ],
                duplicadaDadaDeBaja: true,
                conservadaPasoAEdificio: false,
              ).codificar(),
            ),
          );
      return trabajoId;
    }

    const preguntados = ['esp-pasado', 'esp-fundido', 'esp-unico-a', 'esp-otro'];

    test('mientras el trabajo no se aplicó, el pull no los pisa; los demás espacios, sí', () async {
      await unir();

      expect(await cola.withUnapplied('espacio', preguntados), {'esp-pasado', 'esp-fundido'});
      expect(
        await cola.withUnapplied('ubicacion', preguntados),
        isEmpty,
        reason: 'solo cuenta para espacio',
      );

      await cola.claimPending(limit: 10);
      expect(await cola.withUnapplied('espacio', preguntados), {
        'esp-pasado',
        'esp-fundido',
      }, reason: 'IN_FLIGHT tampoco está aplicado');
    });

    test('aplicado en el servidor (DONE), el pull los vuelve a traer', () async {
      final trabajoId = await unir();
      await cola.claimPending(limit: 10);
      await cola.markDone([trabajoId], at: DateTime.utc(2026, 11, 12, 1));

      expect(await cola.withUnapplied('espacio', preguntados), isEmpty);
    });

    test('rechazado (INVALID) o ya deshecha, tampoco los protege', () async {
      final trabajoId = await unir();
      await cola.claimPending(limit: 10);
      await cola.markInvalid(trabajoId, code: 'UB003', message: 'rechazada');
      expect(await cola.withUnapplied('espacio', preguntados), isEmpty);

      final otra = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      abiertas.add(otra);
      db = otra;
      cola = DriftJobStore(otra);
      await unir(estado: EstadoUnionLocal.deshecha);
      expect(await cola.withUnapplied('espacio', preguntados), isEmpty);
    });
  });
}
