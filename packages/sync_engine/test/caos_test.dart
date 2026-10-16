// Invariantes del motor bajo secuencias aleatorias.
//
// Los tests de ejemplo verifican los casos que alguien pensó. Un motor de sync
// se rompe en los que no: la falla que cae justo entre el claim y el markDone,
// el reintento que llega después de que el servidor ya aplicó, el ciclo que se
// corta a la mitad de un lote. Acá se generan esas secuencias con una semilla
// fija —así un fallo se reproduce— y se verifica lo único que no puede pasar
// nunca, pase lo que pase:
//
//   1. Ningún job queda colgado: al final está DONE o INVALID.
//   2. Cero duplicados: una venta subida N veces es una fila.
//   3. Nada se pierde: todo job DONE está en el servidor.
//   4. Nada se inventa: en el servidor no hay nada que no se haya stageado.
//   5. El watermark nunca retrocede.

import 'dart:math';

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {'venta', 'visita', 'jornada', 'producto', 'persona'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta', critical: true),
      SyncSpec.push('visita'),
      SyncSpec.push('jornada'),
      SyncSpec.pull('producto'),
      SyncSpec.local('persona'),
    ], allEntities: _entidades);

const _pusheables = ['venta', 'visita', 'jornada'];

Future<void> main() async {
  for (var semilla = 1; semilla <= 25; semilla++) {
    test('caos · semilla $semilla', () async {
      final rnd = Random(semilla);
      final jobs = InMemoryJobStore();
      final store = InMemoryLocalStore();
      final transport = FakeSyncTransport();
      final motor = SyncEngine(
        specs: _registro(),
        transport: transport,
        jobs: jobs,
        store: store,
        clock: () => DateTime.utc(2026, 11, 13),
      );

      final stageados = <String, String>{}; // clientOpId → entidad
      final pkPorOpId = <String, String>{};
      final rechazados = <String>{};
      var n = 0;

      // --- la tormenta ------------------------------------------------------
      for (var paso = 0; paso < 60; paso++) {
        switch (rnd.nextInt(10)) {
          case 0:
          case 1:
          case 2:
          case 3:
            // Escribir algo.
            final entidad = _pusheables[rnd.nextInt(_pusheables.length)];
            final opId = 'op-${++n}';
            final pk = 'pk-$n';
            stageados[opId] = entidad;
            pkPorOpId[opId] = pk;
            await motor.stage(entidad, Op.insert, {'id': pk}, clientOpId: opId);
            await motor.flush();

          case 4:
            transport.failTransient(1 + rnd.nextInt(3));

          case 5:
            transport.offline();

          case 6:
            transport.online();

          case 7:
            // La respuesta se pierde después de que el servidor aplicó.
            transport.loseNextResponse();

          case 8:
            // El backend rechaza un job puntual.
            if (stageados.isNotEmpty) {
              final victima =
                  stageados.keys.elementAt(rnd.nextInt(stageados.length));
              transport.rejectJob(victima, 'RECHAZO_SIMULADO');
              rechazados.add(victima);
            }

          case 9:
            await motor.trigger(SyncTrigger.values[rnd.nextInt(3)]);
        }
      }

      // --- que escampe ------------------------------------------------------
      transport.online();
      transport.clearFailures();
      for (var i = 0; i < 12; i++) {
        await motor.syncNow();
        final estado = await jobs.status();
        if (estado.pending == 0 && estado.inFlight == 0) break;
      }

      // --- invariantes ------------------------------------------------------
      final colgados = [
        ...jobs.withState(JobState.pending),
        ...jobs.withState(JobState.inFlight),
      ];
      expect(colgados, isEmpty,
          reason: 'quedaron ${colgados.length} jobs colgados tras 12 ciclos '
              'sin una sola falla: eso es una venta que nunca sube');

      final hechos = jobs.withState(JobState.done);
      final invalidos = jobs.withState(JobState.invalid);
      expect(hechos.length + invalidos.length, stageados.length,
          reason: 'todo job stageado terminó en algún lado');

      for (final entidad in _pusheables) {
        final enServidor =
            transport.rowsOf(entidad).map((f) => f['id']).toSet();

        final esperados = {
          for (final job in hechos)
            if (job.job.entity == entidad) pkPorOpId[job.job.clientOpId]!,
        };

        expect(enServidor, containsAll(esperados),
            reason: '$entidad: hay jobs DONE que no están en el servidor');
        expect(enServidor.length, transport.rowsOf(entidad).length,
            reason: '$entidad: filas duplicadas en el servidor');
        expect(enServidor.difference(esperados), isEmpty,
            reason: '$entidad: el servidor tiene filas que nadie stageó');
      }

      for (final job in invalidos) {
        expect(rechazados, contains(job.job.clientOpId),
            reason: 'un job quedó INVALID sin que el backend lo rechazara');
      }

      await motor.dispose();
    });
  }

  group('bajada', _caosDePull);
}

// ---------------------------------------------------------------------------
// Caos del lado de la bajada: delta, watermark y transacción local.
// ---------------------------------------------------------------------------

void _caosDePull() {
  for (var semilla = 1; semilla <= 15; semilla++) {
    test('caos de pull · semilla $semilla', () async {
      final rnd = Random(semilla * 7919);
      final store = InMemoryLocalStore();
      final transport = FakeSyncTransport();
      final motor = SyncEngine(
        specs: _registro(),
        transport: transport,
        jobs: InMemoryJobStore(),
        store: store,
        clock: () => DateTime.utc(2026, 11, 13),
      );

      final sembradas = <String>{};
      final watermarks = <int>[];
      var n = 0;

      int posicion(String? w) =>
          w == null || w.isEmpty ? 0 : int.parse(w.split('-').last);

      for (var paso = 0; paso < 50; paso++) {
        switch (rnd.nextInt(6)) {
          case 0:
          case 1:
            // Aparece una fila nueva en el servidor.
            final pk = 'prod-${++n}';
            sembradas.add(pk);
            transport.seed('producto', [
              {'id': pk, 'sync_version': 1}
            ]);

          case 2:
            transport.failTransient();

          case 3:
            // La transacción local falla: el watermark no puede avanzar.
            store.failOnApply = true;

          case 4:
            store.failOnApply = false;

          case 5:
            try {
              await motor.syncNow();
            } on StateError {
              // La transacción local explotó; el motor la deja propagar.
            }
            watermarks.add(posicion(store.watermarks['replica']));
        }
      }

      // Que escampe.
      store.failOnApply = false;
      transport
        ..online()
        ..clearFailures();
      for (var i = 0; i < 5; i++) {
        await motor.syncNow();
        watermarks.add(posicion(store.watermarks['replica']));
      }

      // 1. El watermark nunca retrocede: si retrocediera, se rebajarían filas
      //    ya aplicadas y se duplicarían localmente.
      for (var i = 1; i < watermarks.length; i++) {
        expect(watermarks[i], greaterThanOrEqualTo(watermarks[i - 1]),
            reason: 'el watermark retrocedió de ${watermarks[i - 1]} a '
                '${watermarks[i]}');
      }

      // 2. Todo lo que el servidor tenía terminó abajo, exactamente una vez.
      final locales = (store.rows['producto'] ?? const []).map((f) => f['id']);
      expect(locales.toSet(), sembradas,
          reason: 'faltan filas o llegaron de más');
      expect(locales.length, locales.toSet().length,
          reason: 'una fila se aplicó dos veces: el watermark avanzó mal');

      await motor.dispose();
    });
  }
}
