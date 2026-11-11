// La unión rechazada con lo que Ana hizo entre la unión y el rechazo (HU-UBI-006, #696; decisión de
// Cristian, 11/11). Contra la DB real en memoria, con la cola de sync escrita a mano:
// - «Edic. unión»: de las filas que vuelven a B, solo se reenvía (`update`, ya en B) la que tuvo un
//   trabajo después de la unión; las que nadie tocó, no.
// - «Visita unión»: la visita o la entrevista que se le hizo después de unir a una persona que vuelve
//   a B se va con ella y se reenvía; no se borra nada.
import 'dart:convert';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/sync_queue_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart' hide t0;
import '../../../../../helpers/duplicados_falsos.dart' show EncoladorMarcarDuplicadoFalso;
import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 13, 45, 10, 123);
  final tAntes = DateTime.utc(2026, 11, 2, 8);
  final tUnion = DateTime.utc(2026, 11, 2, 9, 0, 0, 250);
  final tDespues = DateTime.utc(2026, 11, 2, 9, 30);
  final tDeshacer = DateTime.utc(2026, 11, 2, 10);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late UbicacionLocalDataSourceDrift local;
  var trabajos = 0;

  UbicacionModel ubicacion(String id) => UbicacionModel(
    id: id,
    tipo: TipoUbicacion.casa,
    calle: 'Av. Italia',
    numero: '1234',
    lat: -34.891,
    lon: -56.125,
    ciudadId: 'ciu-1',
    zonaId: 'zona-9',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1', syncVersion: 4),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: EncoladorMarcarDuplicadoFalso(),
      estadoDeLasCasas: HouseStatusUpdaterEspia(),
    );
  });
  tearDown(() => db.close());

  /// Un trabajo de la cola sobre la fila [rowPk] de [entidad], como lo deja el motor.
  Future<void> trabajo(
    String entidad,
    String rowPk, {
    required DateTime creado,
    String op = 'update',
    String estado = EstadoJob.done,
    Map<String, Object?>? payload,
    String? id,
  }) => db
      .into(db.syncQueue)
      .insertOnConflictUpdate(
        SyncQueueCompanion.insert(
          id: id ?? 'job-${++trabajos}',
          clientOpId: 'op-${id ?? trabajos}',
          entity: entidad,
          op: op,
          payload: jsonEncode(payload ?? {'id': rowPk}),
          rowPk: Value(rowPk),
          createdAt: creado,
          state: estado,
        ),
      );

  /// El trabajo de la unión (`trabajo-1` del falso), rechazado.
  Future<void> rechazarLaUnion() => trabajo(
    'ubicacion',
    'ub-b',
    id: 'trabajo-1',
    creado: tUnion,
    op: 'marcar_como_duplicado',
    estado: EstadoJob.invalid,
  );

  Future<EspacioFila> espacio(String id) =>
      (db.select(db.espacios)..where((e) => e.id.equals(id))).getSingle();
  Future<VisitaFila> visita(String id) =>
      (db.select(db.visitas)..where((e) => e.id.equals(id))).getSingle();
  Future<AgendaFila> agenda(String id) =>
      (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle();

  /// Lo que se encoló al deshacer, sin el `update` del tipo de A (`entidad:operación:id`).
  List<String> reenviados() => [
    for (final c in encolador.encolados)
      if (c.entidad != 'ubicacion') '${c.entidad}:${c.operacion.name}:${c.payload['id']}',
  ];

  Map<String, Object?> payloadDe(String entidad, String id) =>
      encolador.encolados.lastWhere((c) => c.entidad == entidad && c.payload['id'] == id).payload;

  /// A: casa con su único `esp-a` y su persona `ep-a`. B: casa con su único `esp-b` (persona `ep-b`,
  /// una visita y una entrevista) y un depto `esp-b2`. Otra casa C con una entrevista y un vínculo que
  /// nombran a B como casa alternativa.
  Future<void> sembrarPar() async {
    await local.insertar(ubicacion('ub-a'));
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
    await sembrarVinculo(db, id: 'ep-a', espacioId: 'esp-a', personaId: 'per-a');
    await local.insertar(ubicacion('ub-b'));
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');
    await sembrarEspacio(db, id: 'esp-b2', ubicacionId: 'ub-b', numeroDepto: '2B');
    await sembrarVinculo(db, id: 'ep-b', espacioId: 'esp-b', personaId: 'per-b');
    await insertarVisita(db, visitaDe('vis-b', espacio: 'esp-b', vinculo: 'ep-b'));
    await insertarAgenda(db, agendaDe('ag-b', espacio: 'esp-b', vinculo: 'ep-b'));
    await local.insertar(ubicacion('ub-c'));
    await sembrarEspacio(db, id: 'esp-c', ubicacionId: 'ub-c');
    await sembrarVinculo(db, id: 'ep-c', espacioId: 'esp-c', personaId: 'per-c');
    await insertarAgenda(db, agendaDe('ag-c', espacio: 'esp-c', vinculo: 'ep-c'));
    await (db.update(db.agendas)..where((a) => a.id.equals('ag-c'))).write(
      const AgendasCompanion(ubicacionAltId: Value('ub-b')),
    );
    await (db.update(db.espacioPersonas)..where((e) => e.id.equals('ep-c'))).write(
      const EspacioPersonasCompanion(ubicacionCobranzaAltId: Value('ub-b')),
    );
    // El alta de cada fila, antes de unir: no cuenta como «tocada después».
    for (final (entidad, id) in [
      ('espacio', 'esp-b'),
      ('espacio', 'esp-b2'),
      ('espacio_persona', 'ep-b'),
      ('visita', 'vis-b'),
      ('agenda', 'ag-b'),
      ('agenda', 'ag-c'),
      ('espacio_persona', 'ep-c'),
    ]) {
      await trabajo(entidad, id, creado: tAntes, op: 'insert');
    }
  }

  Future<void> unir() async {
    await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
    encolador.encolados.clear();
  }

  Future<void> deshacer() async {
    await rechazarLaUnion();
    final [deshecha] = await local.deshacerUnionesRechazadas(ahora: tDeshacer);
    expect(deshecha.codigo, isEmpty);
  }

  group('«Edic. unión»: se reenvía lo que se editó después de unir', () {
    test('dado que nadie tocó nada después de unir, cuando se deshace, no se reenvía ninguna fila '
        '(solo el tipo de A)', () async {
      await sembrarPar();
      await unir();

      await deshacer();

      expect(reenviados(), isEmpty);
      expect(encolador.encolados.map((c) => c.entidad), ['ubicacion']);
    });

    test(
      'dado el depto de B editado después de unir (su trabajo subió con A), cuando se deshace, se '
      'encola su update ya en B, y el resto no',
      () async {
        await sembrarPar();
        await unir();
        await trabajo(
          'espacio',
          'esp-b2',
          creado: tDespues,
          payload: {'id': 'esp-b2', 'ubicacion_id': 'ub-a', 'numero_depto': '2C'},
        );

        await deshacer();

        expect(reenviados(), ['espacio:update:esp-b2']);
        expect(payloadDe('espacio', 'esp-b2')['ubicacion_id'], 'ub-b');
        expect((await espacio('esp-b2')).ubicacionId, 'ub-b');
      },
    );

    test(
      'dado un trabajo del depto anterior a la unión que todavía lo tiene en B, cuando se deshace, '
      'no se reenvía',
      () async {
        await sembrarPar();
        await trabajo(
          'espacio',
          'esp-b2',
          creado: tAntes,
          estado: EstadoJob.pending,
          payload: {'id': 'esp-b2', 'ubicacion_id': 'ub-b'},
        );
        await unir();

        await deshacer();

        expect(reenviados(), isEmpty);
      },
    );

    test(
      'dado una edición posterior que el motor fundió en un trabajo de antes de unir (conserva el '
      'created_at viejo pero lleva el depto en A), cuando se deshace, se reenvía',
      () async {
        await sembrarPar();
        await unir();
        await trabajo(
          'espacio',
          'esp-b2',
          creado: tAntes,
          estado: EstadoJob.pending,
          payload: {'id': 'esp-b2', 'ubicacion_id': 'ub-a', 'numero_depto': '2C'},
        );

        await deshacer();

        expect(reenviados(), ['espacio:update:esp-b2']);
        expect(payloadDe('espacio', 'esp-b2')['ubicacion_id'], 'ub-b');
      },
    );

    test(
      'dado que la edición posterior volvió INVALID (nunca llegó al servidor), cuando se deshace, '
      'no se reenvía',
      () async {
        await sembrarPar();
        await unir();
        await trabajo(
          'espacio',
          'esp-b2',
          creado: tDespues,
          estado: EstadoJob.invalid,
          payload: {'id': 'esp-b2', 'ubicacion_id': 'ub-a'},
        );

        await deshacer();

        expect(reenviados(), isEmpty);
      },
    );

    test(
      'dado la persona, la visita, la entrevista y las alternativas de B editadas después de unir, '
      'cuando se deshace, cada una se reenvía una vez y en orden, ya en B',
      () async {
        await sembrarPar();
        await unir();
        for (final (entidad, id) in [
          ('agenda', 'ag-c'),
          ('agenda', 'ag-b'),
          ('visita', 'vis-b'),
          ('espacio_persona', 'ep-c'),
          ('espacio_persona', 'ep-b'),
          ('espacio_persona', 'ep-b'),
        ]) {
          await trabajo(entidad, id, creado: tDespues);
        }

        await deshacer();

        expect(reenviados(), [
          'espacio_persona:update:ep-b',
          'espacio_persona:update:ep-c',
          'visita:update:vis-b',
          'agenda:update:ag-b',
          'agenda:update:ag-c',
        ]);
        expect(payloadDe('espacio_persona', 'ep-b')['espacio_id'], 'esp-b');
        expect(payloadDe('espacio_persona', 'ep-c')['ubicacion_cobranza_alt_id'], 'ub-b');
        expect(payloadDe('visita', 'vis-b')['espacio_id'], 'esp-b');
        expect(payloadDe('agenda', 'ag-b')['espacio_id'], 'esp-b');
        expect(payloadDe('agenda', 'ag-c')['ubicacion_alt_id'], 'ub-b');
        expect(
          encolador.encolados.where((c) => c.entidad != 'ubicacion').map((c) => c.operacion),
          everyElement(OperacionSync.update),
        );
      },
    );

    test('dado dos avisos seguidos del rechazo, cuando se deshace, lo editado se reenvía una sola '
        'vez', () async {
      await sembrarPar();
      await unir();
      await trabajo('espacio', 'esp-b2', creado: tDespues);
      await rechazarLaUnion();

      final [primera, segunda] = await Future.wait([
        local.deshacerUnionesRechazadas(ahora: tDeshacer),
        local.deshacerUnionesRechazadas(ahora: tDeshacer),
      ]);

      expect(primera.length + segunda.length, 1);
      expect(reenviados(), ['espacio:update:esp-b2']);
    });
  });

  group('«Visita unión»: lo nuevo de la persona que vuelve a B va con ella', () {
    test('dado una visita y una entrevista nuevas de la persona de B en el único de A, cuando se '
        'deshace, vuelven a B con ella y se reenvían; las de la persona de A se quedan', () async {
      await sembrarPar();
      await unir();
      await insertarVisita(
        db,
        visitaDe('vis-n', espacio: 'esp-a', vinculo: 'ep-b', creada: tDespues),
      );
      await insertarAgenda(
        db,
        agendaDe('ag-n', espacio: 'esp-a', vinculo: 'ep-b', creada: tDespues),
      );
      await insertarVisita(
        db,
        visitaDe('vis-a', espacio: 'esp-a', vinculo: 'ep-a', creada: tDespues),
      );
      await insertarAgenda(
        db,
        agendaDe('ag-a', espacio: 'esp-a', vinculo: 'ep-a', creada: tDespues),
      );
      for (final (entidad, id) in [
        ('visita', 'vis-n'),
        ('agenda', 'ag-n'),
        ('visita', 'vis-a'),
        ('agenda', 'ag-a'),
      ]) {
        await trabajo(entidad, id, creado: tDespues, op: 'insert', estado: EstadoJob.done);
      }

      await deshacer();

      expect((await visita('vis-n')).espacioId, 'esp-b');
      expect((await agenda('ag-n')).espacioId, 'esp-b');
      expect((await visita('vis-a')).espacioId, 'esp-a');
      expect((await agenda('ag-a')).espacioId, 'esp-a');
      expect(reenviados(), ['visita:update:vis-n', 'agenda:update:ag-n']);
      expect(payloadDe('visita', 'vis-n')['espacio_id'], 'esp-b');
      expect(payloadDe('visita', 'vis-n')['espacio_persona_id'], 'ep-b');
      expect(payloadDe('agenda', 'ag-n')['espacio_id'], 'esp-b');
      // Nada se borró.
      expect(await db.select(db.visitas).get(), hasLength(3));
      expect(await db.select(db.agendas).get(), hasLength(4));
    });

    test('dado una visita nueva de baja (historial) de la persona de B, cuando se deshace, también '
        'vuelve con ella', () async {
      await sembrarPar();
      await unir();
      await insertarVisita(
        db,
        visitaDe('vis-n', espacio: 'esp-a', vinculo: 'ep-b', creada: tDespues, borrada: tDespues),
      );
      await trabajo('visita', 'vis-n', creado: tDespues, op: 'insert');

      await deshacer();

      final fila = await visita('vis-n');
      expect(fila.espacioId, 'esp-b');
      expect(fila.deletedAt, isNotNull, reason: 'sigue de baja: solo cambia de espacio');
      expect(reenviados(), ['visita:update:vis-n']);
    });

    test(
      'dado que la persona de B ya no está en el único de A (se movió después), cuando se deshace, '
      'no vuelve, y su visita nueva tampoco',
      () async {
        await sembrarPar();
        await unir();
        await (db.update(db.espacioPersonas)..where((e) => e.id.equals('ep-b'))).write(
          const EspacioPersonasCompanion(espacioId: Value('esp-c')),
        );
        await insertarVisita(
          db,
          visitaDe('vis-n', espacio: 'esp-c', vinculo: 'ep-b', creada: tDespues),
        );
        await trabajo('visita', 'vis-n', creado: tDespues, op: 'insert');
        await rechazarLaUnion();

        final [deshecha] = await local.deshacerUnionesRechazadas(ahora: tDeshacer);

        expect(deshecha.sinVolver, 1, reason: 'el vínculo que se movió después');
        expect((await visita('vis-n')).espacioId, 'esp-c');
        expect(reenviados(), isNot(contains('visita:update:vis-n')));
      },
    );
  });
}
