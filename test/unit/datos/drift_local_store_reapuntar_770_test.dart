// Contrato §2.3 «Venta tarde» (#770, seguimiento de #766): cuando el servidor junta el vínculo de la
// colportora con el que ya tenía (`merged` + `merged_into`), el teléfono reapunta lo local al que
// quedó, sin borrar nada. Contra las tablas reales (AppDatabase en memoria) y el motor de verdad.
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';

/// El servidor: junta el alta del vínculo `op-vinculo` con `ep-y` y acepta el resto.
final class _Servidor implements SyncTransport {
  int pushes = 0;

  @override
  Future<PushResult> push(PushBatch batch) async {
    pushes++;
    return PushResult(
      serverTime: DateTime.utc(2026, 11, 25, 12),
      results: [
        for (final j in batch.jobs)
          if (j.clientOpId == 'op-vinculo')
            JobResult(clientOpId: j.clientOpId, outcome: JobOutcome.merged, mergedInto: 'ep-y')
          else
            JobResult(clientOpId: j.clientOpId, outcome: JobOutcome.accepted, syncVersion: 1),
      ],
    );
  }

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) async =>
      PullDelta(
        serverTime: DateTime.utc(2026, 11, 25, 12),
        watermark: watermark ?? 'w-0',
        hasMore: false,
        rows: const {},
      );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftLocalStore store;
  late DriftJobStore cola;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
    cola = DriftJobStore(db);
  });
  tearDown(() => db.close());

  Future<void> venta(String id, String vinculo) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: vinculo,
          numeroTalonario: 'T-$id',
          montoTotal: 150000,
          fecha: t0,
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  /// Ana cargó a Pedro (`ep-x`, en el espacio B) y una venta, una visita y una agenda con él, sin
  /// señal. Mientras tanto Pedro ya tenía su vínculo en A (`ep-y`, el que el servidor deja).
  Future<void> sembrarCasoDeAna({bool conElDeA = true}) async {
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');
    await sembrarVinculo(db, id: 'ep-x', espacioId: 'esp-b', personaId: 'per-1');
    if (conElDeA) {
      await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
      await sembrarVinculo(db, id: 'ep-y', espacioId: 'esp-a', personaId: 'per-1');
    }
    await insertarVisita(
      db,
      visitaDe('vis-1', espacio: 'esp-b', vinculo: 'ep-x', resultado: TipoResultadoVisita.venta),
    );
    await insertarAgenda(db, agendaDe('ag-1', espacio: 'esp-b', vinculo: 'ep-x'));
    await venta('ven-1', 'ep-x');
  }

  Future<Map<String, String?>> vinculosNombrados() async => {
    for (final v in await db.select(db.visitas).get()) v.id: v.espacioPersonaId,
    for (final a in await db.select(db.agendas).get()) a.id: a.espacioPersonaId,
    for (final v in await db.select(db.ventas).get()) v.id: v.espacioPersonaId,
  };

  Future<Set<String>> idsDeVinculos() async => {
    for (final v in await db.select(db.espacioPersonas).get()) v.id,
  };

  group('DriftLocalStore.reapuntar (vínculo juntado)', () {
    test('la visita, la agenda y la venta que nombraban al vínculo pasan al que quedó, y no se '
        'borra ninguna fila', () async {
      await sembrarCasoDeAna();

      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y');

      expect(await vinculosNombrados(), {'vis-1': 'ep-y', 'ag-1': 'ep-y', 'ven-1': 'ep-y'});
      expect(
        await idsDeVinculos(),
        {'ep-x', 'ep-y'},
        reason: 'el de A ya estaba en el teléfono: no se pisa ni se borra ninguno',
      );
      expect(await db.select(db.visitas).get(), hasLength(1));
      expect(await db.select(db.agendas).get(), hasLength(1));
      expect(await db.select(db.ventas).get(), hasLength(1));
    });

    test('lo que nombra a otro vínculo no se toca', () async {
      await sembrarCasoDeAna();
      await sembrarVinculo(db, id: 'ep-w', espacioId: 'esp-b', personaId: 'per-2');
      await venta('ven-2', 'ep-w');

      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y');

      expect((await vinculosNombrados())['ven-2'], 'ep-w');
    });

    test('si el teléfono todavía no tiene el vínculo que quedó, la fila del vínculo pasa a '
        'llamarse así (sin borrarla)', () async {
      await sembrarCasoDeAna(conElDeA: false);

      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y');

      expect(await idsDeVinculos(), {'ep-y'});
      final fila = await db.select(db.espacioPersonas).getSingle();
      expect((fila.espacioId, fila.personaId), ('esp-b', 'per-1'));
      expect((await vinculosNombrados()).values, everyElement('ep-y'));
    });

    test('la cola no se reescribe: lo encolado que nombra al vínculo viejo sale como estaba y la '
        'fila local queda en el que quedó (decisión del 25/11, mapa §2)', () async {
      await sembrarCasoDeAna();
      final payload = {'id': 'ven-1', 'espacio_persona_id': 'ep-x', 'monto_total': 150000};
      final id = await cola.append(
        SyncJob(
          clientOpId: 'op-venta',
          entity: 'venta',
          op: Op.insert,
          payload: payload,
          createdAt: t0,
          rowPk: 'ven-1',
        ),
      );
      final delVinculo = await cola.append(
        SyncJob(
          clientOpId: 'op-edicion',
          entity: 'espacio_persona',
          op: Op.update,
          payload: {'id': 'ep-x', 'espacio_id': 'esp-b', 'persona_id': 'per-1'},
          createdAt: t0,
          rowPk: 'ep-x',
        ),
      );
      final antes = await db.select(db.syncQueue).get();

      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y');

      expect(await db.select(db.syncQueue).get(), antes, reason: 'la cola queda idéntica');
      final fila = await (db.select(db.syncQueue)..where((q) => q.id.equals(id))).getSingle();
      expect(jsonDecode(fila.payload), payload);
      expect(
        (await (db.select(db.syncQueue)..where((q) => q.id.equals(delVinculo))).getSingle()).rowPk,
        'ep-x',
        reason:
            'el servidor pasa solo un update del vínculo viejo al que quedó (§2.3, Edición tarde)',
      );
      expect((await vinculosNombrados())['ven-1'], 'ep-y');
    });

    test('después del pull, Pedro no sale dos veces en la ficha de A: el vínculo viejo queda en el '
        'espacio fundido de B, que el servidor da de baja (decisión del 25/11, mapa §2)', () async {
      await sembrarCasoDeAna();
      await db
          .into(db.personas)
          .insert(
            PersonasCompanion.insert(id: 'per-1', nombre: 'Pedro', createdAt: t0, updatedAt: t0),
          );
      final personas = PersonaLocalDataSourceDrift(db, encolador: EncoladorSyncEnMemoria());

      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y');
      // El pull trae la unión: el espacio único de B queda de baja.
      await store.applyDelta(
        {
          'espacio': [
            {
              'id': 'esp-b',
              'ubicacion_id': 'ub-b',
              'created_at': '2026-10-23T13:45:10.123Z',
              'updated_at': '2026-11-25T12:00:00.000Z',
              'deleted_at': '2026-11-25T12:00:00.000Z',
              'sync_version': 2,
            },
          ],
        },
        scope: 'mirror',
        watermark: 'w1',
      );

      final laFichaDeA = await personas.observarDelEspacio('esp-a').first;
      expect(
        [for (final p in laFichaDeA) (p.persona.id, p.vinculo.id)],
        [('per-1', 'ep-y')],
        reason: 'Pedro una sola vez, con el vínculo que quedó',
      );
      final b = await (db.select(db.espacios)..where((e) => e.id.equals('esp-b'))).getSingle();
      expect(b.deletedAt, isNotNull);
      expect(await idsDeVinculos(), {'ep-x', 'ep-y'}, reason: 'no se borra ni se da de baja nada');
    });

    test('es idempotente: la segunda vez no hay nada que reapuntar y no falla', () async {
      await sembrarCasoDeAna();

      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y');
      final primera = await vinculosNombrados();
      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y');

      expect(await vinculosNombrados(), primera);
      expect(await idsDeVinculos(), {'ep-x', 'ep-y'});
    });

    test('de y a iguales: no hace nada', () async {
      await sembrarCasoDeAna();

      await store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-x');

      expect((await vinculosNombrados())['ven-1'], 'ep-x');
    });

    test('una entidad sin referencias conocidas no hace nada ni traba la cola', () async {
      await sembrarCasoDeAna();

      await store.reapuntar('jornada', de: 'a', a: 'b');

      expect((await vinculosNombrados())['ven-1'], 'ep-x');
    });

    test('una entidad que no es del motor sí es un error de programación', () async {
      expect(() => store.reapuntar('no_existe', de: 'a', a: 'b'), throwsA(isA<ArgumentError>()));
    });

    test('es atómica: si algo falla en la mitad no queda una venta reapuntada y otra no', () async {
      await sembrarCasoDeAna();
      // Rompe la última escritura (la de la fila del vínculo): la DB local falla a la mitad.
      await db.customStatement('''
        CREATE TRIGGER falla_al_renombrar BEFORE UPDATE OF id ON espacio_persona
        BEGIN SELECT RAISE(ABORT, 'falla simulada'); END;
      ''');
      await db.customStatement("DELETE FROM espacio_persona WHERE id = 'ep-y'");

      await expectLater(
        store.reapuntar('espacio_persona', de: 'ep-x', a: 'ep-y'),
        throwsA(anything),
      );

      expect(
        (await vinculosNombrados()).values,
        everyElement('ep-x'),
        reason: 'la transacción se revirtió entera',
      );
    });
  });

  group('de punta a punta: el motor recibe merged', () {
    test('Ana vendió sin señal en B, B se unió a A: tras subir, la venta y lo suyo quedan en el '
        'vínculo de A y el job del alta sale de la cola', () async {
      await sembrarCasoDeAna();
      final servidor = _Servidor();
      final motor = SyncEngine(
        specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
        transport: servidor,
        jobs: cola,
        store: store,
      );
      await motor.stage('espacio_persona', Op.insert, {
        'id': 'ep-x',
        'espacio_id': 'esp-b',
        'persona_id': 'per-1',
      }, clientOpId: 'op-vinculo');
      await motor.stage('venta', Op.insert, {
        'id': 'ven-1',
        'espacio_persona_id': 'ep-x',
      }, clientOpId: 'op-venta');

      final salida = await motor.syncNow();
      await motor.dispose();

      expect(salida.invalidated, 0);
      expect(await vinculosNombrados(), {'vis-1': 'ep-y', 'ag-1': 'ep-y', 'ven-1': 'ep-y'});
      final estados = {for (final q in await db.select(db.syncQueue).get()) q.clientOpId: q.state};
      expect(estados, {'op-vinculo': 'DONE', 'op-venta': 'DONE'});
    });

    test(
      'si la DB falla al reapuntar, el alta no queda cerrada: se reintenta y entonces sí',
      () async {
        await sembrarCasoDeAna();
        final servidor = _Servidor();
        final motor = SyncEngine(
          specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
          transport: servidor,
          jobs: cola,
          store: store,
        );
        await motor.stage('espacio_persona', Op.insert, {
          'id': 'ep-x',
          'espacio_id': 'esp-b',
          'persona_id': 'per-1',
        }, clientOpId: 'op-vinculo');
        await db.customStatement('''
        CREATE TRIGGER falla_una_vez BEFORE UPDATE ON venta
        BEGIN SELECT RAISE(ABORT, 'falla simulada'); END;
      ''');

        await expectLater(motor.syncNow(), throwsA(anything));
        var estados = {for (final q in await db.select(db.syncQueue).get()) q.clientOpId: q.state};
        expect(estados['op-vinculo'], 'PENDING', reason: 'ni cerrado ni trabado en vuelo');

        await db.customStatement('DROP TRIGGER falla_una_vez');
        await motor.syncNow();
        await motor.dispose();

        estados = {for (final q in await db.select(db.syncQueue).get()) q.clientOpId: q.state};
        expect(estados['op-vinculo'], 'DONE');
        expect((await vinculosNombrados())['ven-1'], 'ep-y');
      },
    );
  });
}
