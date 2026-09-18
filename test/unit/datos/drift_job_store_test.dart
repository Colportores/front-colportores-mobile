// El contrato de `JobStorePort`, corrido contra la implementación real.
//
// `runJobStoreContract` lo publica el propio motor (`package:sync_engine/port_contracts.dart`): es
// la definición ejecutable del puerto, la misma que pasa el `InMemoryJobStore` con el que se
// verificó cada invariante del engine. Si esto pasa, el motor se comporta sobre la DB igual que en
// la VM; sin esto, nada garantiza que un `claimPending` sobre SQL devuelva lo mismo que el fake.
//
// Abajo del contrato van los tests de lo que es propio de esta implementación y el contrato no
// puede saber: que la cola sobrevive al cierre de la app, y que crearla no le toca el esquema a
// `AppDatabase`.

import 'dart:io';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:sync_engine/port_contracts.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

/// El log de migraciones de `AppDatabase` no aporta nada acá y ensucia la salida de 20 tests.
class _SinSalida extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

AppDatabase _db([QueryExecutor? e]) =>
    AppDatabase(e ?? NativeDatabase.memory(), logger: AppLogger(output: _SinSalida()));

SyncJob _venta(String opId) => SyncJob(
  clientOpId: opId,
  entity: 'venta',
  op: Op.insert,
  payload: {'id': 'pk-$opId', 'monto_total': 45000, 'notas': null},
  createdAt: DateTime.utc(2026, 11, 13, 8),
);

void main() {
  // Cada caso del contrato abre su propia base en memoria, y drift avisa cuando ve dos instancias
  // de la misma clase. Acá es lo esperado: son ejecutores distintos, no la misma base dos veces.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  runJobStoreContract('DriftJobStore', () => DriftJobStore(_db()));

  group('DriftJobStore · lo que agrega estar en la DB', () {
    late Directory carpeta;
    late File archivo;

    setUp(() {
      carpeta = Directory.systemTemp.createTempSync('sync_queue_test');
      archivo = File('${carpeta.path}/local.sqlite');
    });

    tearDown(() => carpeta.deleteSync(recursive: true));

    test('una venta encolada sobrevive a que se cierre la app', () async {
      final primera = _db(NativeDatabase(archivo));
      final id = await DriftJobStore(primera).append(_venta('op-1'));
      await primera.close();

      // La app arrancó de nuevo: otra conexión, otro store, la misma base.
      final segunda = _db(NativeDatabase(archivo));
      addTearDown(segunda.close);
      final cola = DriftJobStore(segunda);

      expect((await cola.status()).pending, 1);
      final tomados = await cola.claimPending(limit: 10);
      expect(tomados.single.id, id);
      expect(
        tomados.single.job.clientOpId,
        'op-1',
        reason: 'el mismo client_op_id, o el servidor no puede deduplicar el reintento (§5.3)',
      );
      expect(
        tomados.single.job.payload['monto_total'],
        45000,
        reason: 'el payload vuelve como se guardó, sin pasar por String',
      );
      expect(
        tomados.single.job.payload.containsKey('notas'),
        isTrue,
        reason: 'un null del payload es un dato, no una clave ausente',
      );
    });

    test('dos stores sobre la misma base no se pisan al crear la cola', () async {
      final db = _db(NativeDatabase(archivo));
      addTearDown(db.close);

      await DriftJobStore(db).append(_venta('op-1'));
      await DriftJobStore(db).append(_venta('op-2'));

      expect(
        (await DriftJobStore(db).status()).pending,
        2,
        reason: 'el DDL es IF NOT EXISTS: el segundo store encuentra la tabla hecha',
      );
    });

    test('crear la cola no le toca el esquema a AppDatabase', () async {
      final db = _db(NativeDatabase(archivo));
      addTearDown(db.close);

      await DriftJobStore(db).append(_venta('op-1'));

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        version.read<int>('user_version'),
        db.schemaVersion,
        reason: 'la cola es del motor: la versión del esquema la manda el dominio (#8)',
      );
      expect(
        db.allTables,
        isEmpty,
        reason: 'sync_queue no entra en allTables mientras no exista drift_dev',
      );
    });

    test('el reintento del mismo client_op_id no entra dos veces', () async {
      final db = _db(NativeDatabase(archivo));
      addTearDown(db.close);
      final cola = DriftJobStore(db);
      await cola.append(_venta('op-1'));

      // Encolar dos veces el mismo intento es un bug del llamador y se corta acá, no en el
      // servidor: si entrara, el ciclo gastaría dos viajes para que el segundo vuelva `duplicate`.
      await expectLater(cola.append(_venta('op-1')), throwsA(isA<Exception>()));
      expect((await cola.status()).pending, 1);
    });
  });
}
