// HU-UBI-006 (paraguas #138), «Marcar como duplicado y conservar A»: lo que colgaba del espacio
// único fundido de B (personas, visitas y agendas) pasa al único de A, y el color de las dos casas
// se recalcula, todo en la misma transacción. Contra las tablas reales (AppDatabase en memoria).
// Los escenarios llevan el título de la HU.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/duplicados_ubicacion_use_cases.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/duplicados_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 27, 9);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late EncoladorMarcarDuplicadoFalso marcador;
  late UnirDuplicadosUseCase unir;

  UnirDuplicadosUseCase armar({HouseStatusUpdaterEspia? estado}) {
    final local = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: marcador,
      estadoDeLasCasas: estado,
    );
    return UnirDuplicadosUseCase(
      UbicacionRepositoryImpl(local, logger: loggerMudo()),
      ahora: () => ahora,
    );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    marcador = EncoladorMarcarDuplicadoFalso();
    unir = armar();
  });

  tearDown(() => db.close());

  Future<void> ubicacion(String id, {String tipo = 'CASA', double lat = -34.9}) => db
      .into(db.ubicaciones)
      .insert(
        UbicacionesCompanion.insert(
          id: id,
          tipo: tipo,
          lat: lat,
          lon: -56.16,
          ciudadId: 'ciu-1',
          createdAt: t0,
          updatedAt: t0,
          createdBy: const Value('col-1'),
        ),
      );

  Future<void> unirBAEnA() async {
    final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));
    expect(r.isRight(), isTrue, reason: 'la unión tenía que salir bien');
  }

  /// El estado de la cache de la casa: `null` si no tiene fila; si no, (color, de baja).
  Future<(String, bool)?> casaEnElMapa(String ubicacionId) async {
    final fila = await (db.select(
      db.houseStatuses,
    )..where((h) => h.ubicacionId.equals(ubicacionId))).getSingleOrNull();
    return fila == null ? null : (fila.color, fila.deletedAt != null);
  }

  Future<Map<String, String>> vinculos() async => {
    for (final v in await db.select(db.espacioPersonas).get()) v.id: v.espacioId,
  };

  Future<Map<String, String>> visitas() async => {
    for (final v in await db.select(db.visitas).get()) v.id: v.espacioId,
  };

  Future<Map<String, String>> agendas() async => {
    for (final a in await db.select(db.agendas).get()) a.id: a.espacioId,
  };

  Future<bool> espacioDeBaja(String id) async =>
      (await (db.select(db.espacios)..where((e) => e.id.equals(id))).getSingle()).deletedAt != null;

  /// A y B, casas con su espacio único cada una; el de B con dos personas, una venta y una agenda.
  Future<void> sembrarCasasConGente() async {
    await ubicacion('ub-a');
    await ubicacion('ub-b', lat: -34.9001);
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');
    await sembrarVinculo(db, id: 'ep-a1', espacioId: 'esp-a', personaId: 'per-a1');
    await sembrarVinculo(db, id: 'ep-b1', espacioId: 'esp-b', personaId: 'per-b1');
    await sembrarVinculo(db, id: 'ep-b2', espacioId: 'esp-b', personaId: 'per-b2');
    await insertarVisita(
      db,
      visitaDe('vis-b1', espacio: 'esp-b', vinculo: 'ep-b1', resultado: TipoResultadoVisita.venta),
    );
    await insertarAgenda(db, agendaDe('ag-b1', espacio: 'esp-b', vinculo: 'ep-b2'));
  }

  group('Escenario: Marcar como duplicado y conservar A', () {
    test(
      'dado que B tiene un espacio con 2 personas y una venta, cuando se une, en mi teléfono '
      'pasa a A todo lo que colgaba de B, y el espacio de B queda de baja sin borrar nada',
      () async {
        await sembrarCasasConGente();

        await unirBAEnA();

        expect(await vinculos(), {'ep-a1': 'esp-a', 'ep-b1': 'esp-a', 'ep-b2': 'esp-a'});
        expect(await visitas(), {'vis-b1': 'esp-a'});
        expect(await agendas(), {'ag-b1': 'esp-a'});
        expect(await espacioDeBaja('esp-b'), isTrue, reason: 'el único de B queda de baja');
        expect(await espacioDeBaja('esp-a'), isFalse);
        final b = await (db.select(db.ubicaciones)..where((u) => u.id.equals('ub-b'))).getSingle();
        expect(b.deletedAt, ahora);
        final log = await db.select(db.auditLogLocal).get();
        expect(
          (log.single.evento, log.single.uuid, log.single.motivo),
          (EventoAuditoriaLocal.ubicacionBaja, 'ub-b', 'duplicado_de_ub-a'),
        );
        expect(marcador.encolados, [(duplicadaId: 'ub-b', conservadaId: 'ub-a')]);
        expect(
          await db.select(db.espacioPersonas).get(),
          everyElement(
            predicate(
              (v) => (v as EspacioPersonaFila).deletedAt == null,
              'ningún vínculo se da de baja',
            ),
          ),
          reason: 'nunca se pierde una persona',
        );
      },
    );

    test('dado que el único de B tiene el número en blanco, cuando se une, también se funde y '
        'lo suyo pasa al único de A', () async {
      await sembrarCasasConGente();
      await (db.update(db.espacios)..where((e) => e.id.equals('esp-b'))).write(
        const EspaciosCompanion(numeroDepto: Value('   ')),
      );

      await unirBAEnA();

      expect(await visitas(), {'vis-b1': 'esp-a'});
      expect(await espacioDeBaja('esp-b'), isTrue);
    });

    test('dado que B tiene visitas y agendas que ya estaban de baja, cuando se une, pasan igual: '
        'el historial se conserva y no cuenta para el color', () async {
      await sembrarCasasConGente();
      await insertarVisita(
        db,
        visitaDe(
          'vis-vieja',
          espacio: 'esp-b',
          vinculo: null,
          resultado: TipoResultadoVisita.rechazo,
          borrada: t0,
        ),
      );
      await insertarAgenda(db, agendaDe('ag-vieja', espacio: 'esp-b', vinculo: null, borrada: t0));

      await unirBAEnA();

      expect((await visitas())['vis-vieja'], 'esp-a');
      expect((await agendas())['ag-vieja'], 'esp-a');
    });

    test(
      'dado que una agenda y un vínculo nombran a B como casa alternativa (y otros a una tercera), '
      'cuando se une, pasan a nombrar a A y lo de la tercera no se toca ni se encola nada por fila',
      () async {
        await sembrarCasasConGente();
        await ubicacion('ub-c', lat: -34.95);
        await insertarAgenda(db, agendaDe('ag-alt', espacio: 'esp-a', vinculo: 'ep-a1'));
        await insertarAgenda(db, agendaDe('ag-otra', espacio: 'esp-a', vinculo: 'ep-a1'));
        await (db.update(db.agendas)..where((x) => x.id.equals('ag-alt'))).write(
          const AgendasCompanion(ubicacionAltId: Value('ub-b')),
        );
        await (db.update(db.agendas)..where((x) => x.id.equals('ag-otra'))).write(
          const AgendasCompanion(ubicacionAltId: Value('ub-c')),
        );
        await (db.update(db.espacioPersonas)..where((x) => x.id.equals('ep-a1'))).write(
          const EspacioPersonasCompanion(ubicacionCobranzaAltId: Value('ub-b')),
        );
        await (db.update(db.espacioPersonas)..where((x) => x.id.equals('ep-b1'))).write(
          const EspacioPersonasCompanion(ubicacionCobranzaAltId: Value('ub-c')),
        );
        encolador.encolados.clear();

        await unirBAEnA();

        final alternativasDeAgendas = {
          for (final x in await db.select(db.agendas).get()) x.id: x.ubicacionAltId,
        };
        expect(alternativasDeAgendas['ag-alt'], 'ub-a');
        expect(alternativasDeAgendas['ag-otra'], 'ub-c');
        final alternativasDeVinculos = {
          for (final x in await db.select(db.espacioPersonas).get()) x.id: x.ubicacionCobranzaAltId,
        };
        expect(alternativasDeVinculos['ep-a1'], 'ub-a');
        expect(alternativasDeVinculos['ep-b1'], 'ub-c');
        expect(
          encolador.encolados.map((c) => c.entidad).toSet().difference({'house_status'}),
          isEmpty,
          reason: 'sin encolar por fila: el servidor reapunta las suyas con el trabajo',
        );
      },
    );

    test(
      'dado que A y B tienen notas del lugar, cuando se une, la hoja de A muestra las de las dos '
      '(también la dada de baja) y las notas de otros objetos no se tocan ni se encola nada',
      () async {
        await sembrarCasasConGente();
        Future<void> nota(String id, String tipo, String objetivo, {DateTime? borrada}) => db
            .into(db.notas)
            .insert(
              NotasCompanion.insert(
                id: id,
                targetType: tipo,
                targetId: objetivo,
                texto: 'texto $id',
                createdAt: t0.add(Duration(minutes: id.length)),
                updatedAt: t0,
                deletedAt: Value(borrada),
              ),
            );
        await nota('n-a', 'UBICACION', 'ub-a');
        await nota('n-b1', 'UBICACION', 'ub-b');
        await nota('n-b22', 'UBICACION', 'ub-b');
        await nota('n-b333', 'UBICACION', 'ub-b', borrada: t0);
        await nota('n-pb', 'PERSONA', 'ub-b');
        encolador.encolados.clear();

        await unirBAEnA();

        final deA = await NotaUbicacionLocalDataSourceDrift(db).observar('ub-a').first;
        expect({for (final n in deA) n.id}, {'n-a', 'n-b1', 'n-b22', 'n-b333'});
        expect(await NotaUbicacionLocalDataSourceDrift(db).observar('ub-b').first, isEmpty);
        final todas = {
          for (final n in await db.select(db.notas).get()) n.id: (n.targetType, n.targetId),
        };
        expect(todas['n-b333'], ('UBICACION', 'ub-a'), reason: 'la de baja pasa igual');
        expect(todas['n-pb'], ('PERSONA', 'ub-b'), reason: 'solo las del lugar');
        expect(
          encolador.encolados.map((c) => c.entidad).toSet().difference({'house_status'}),
          isEmpty,
          reason: 'la nota es solo local: no se encola',
        );
      },
    );

    test(
      'dado que B es un edificio con notas del lugar (su espacio no se funde), cuando se une, las '
      'notas pasan igual a A',
      () async {
        await ubicacion('ub-a');
        await ubicacion('ub-b', tipo: 'EDIFICIO', lat: -34.9001);
        await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
        await sembrarEspacio(db, id: 'dep-1', ubicacionId: 'ub-b', numeroDepto: '1A');
        await db
            .into(db.notas)
            .insert(
              NotasCompanion.insert(
                id: 'n-b',
                targetType: 'UBICACION',
                targetId: 'ub-b',
                texto: 'portero amable',
                createdAt: t0,
                updatedAt: t0,
              ),
            );

        await unirBAEnA();

        final deA = await NotaUbicacionLocalDataSourceDrift(db).observar('ub-a').first;
        expect([for (final n in deA) n.id], ['n-b']);
      },
    );

    test(
      'dado que la unión ya se hizo, cuando se repite, no mueve ni encola nada de más',
      () async {
        await sembrarCasasConGente();
        await unirBAEnA();
        final antes = encolador.encolados.length;
        final marcados = marcador.encolados.length;

        final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

        expect(r.isRight(), isTrue);
        expect(encolador.encolados, hasLength(antes));
        expect(marcador.encolados, hasLength(marcados));
        expect(await visitas(), {'vis-b1': 'esp-a'});
      },
    );
  });

  group('Escenario: El estado de A se recalcula', () {
    // La venta todavía no aporta color (el cálculo la suma en S9, ADR-003): hoy pintan las agendas
    // y las visitas con entrevista, sin respuesta o con rechazo.
    test(
      'dado que A tiene una entrevista programada y B una entrevista hecha, cuando se une, el '
      'color de A se recalcula con los eventos de las dos y la fila de B queda dada de baja',
      () async {
        await ubicacion('ub-a');
        await ubicacion('ub-b', lat: -34.9001);
        await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
        await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');
        await sembrarVinculo(db, id: 'ep-a1', espacioId: 'esp-a', personaId: 'per-a1');
        await sembrarVinculo(db, id: 'ep-b1', espacioId: 'esp-b', personaId: 'per-b1');
        await insertarAgenda(db, agendaDe('ag-a', espacio: 'esp-a', vinculo: 'ep-a1'));
        await insertarVisita(
          db,
          visitaDe(
            'vis-b',
            espacio: 'esp-b',
            vinculo: 'ep-b1',
            resultado: TipoResultadoVisita.entrevista,
          ),
        );
        final updater = HouseStatusUpdaterDrift(db, encolador: encolador);
        await updater.recalcular('ub-a', ahora: t0, colportorId: 'col-1');
        await updater.recalcular('ub-b', ahora: t0, colportorId: 'col-1');
        expect(await casaEnElMapa('ub-a'), ('ENTREVISTA_PROGRAMADA', false));
        expect(await casaEnElMapa('ub-b'), ('ENTREVISTA_SIN_VENTA', false));
        encolador.encolados.clear();

        await unirBAEnA();

        expect(
          await casaEnElMapa('ub-a'),
          ('ENTREVISTA_PROGRAMADA', false),
          reason: 'la entrevista programada (3) le gana a la entrevista sin venta (5)',
        );
        expect(await casaEnElMapa('ub-b'), ('ENTREVISTA_SIN_VENTA', true), reason: 'baja con B');
        expect(
          [
            for (final c in encolador.encolados.where((c) => c.entidad == 'house_status'))
              c.operacion,
          ],
          [OperacionSync.delete],
          reason: 'solo sube la baja de la fila de B: la de A no cambió de color',
        );
      },
    );

    test('dado que A no tenía nada y B tiene una visita sin respuesta, cuando se une, A pasa a '
        '«Sin contestar» y B deja de pintar el mapa', () async {
      await sembrarCasasConGente();
      await (db.delete(db.agendas)).go();
      await (db.delete(db.visitas)).go();
      await insertarVisita(
        db,
        visitaDe(
          'vis-nc',
          espacio: 'esp-b',
          vinculo: null,
          resultado: TipoResultadoVisita.noContesto,
        ),
      );
      final updater = HouseStatusUpdaterDrift(db, encolador: encolador);
      await updater.recalcular('ub-b', ahora: t0, colportorId: 'col-1');
      expect(await casaEnElMapa('ub-a'), isNull);
      encolador.encolados.clear();

      await unirBAEnA();

      expect(await casaEnElMapa('ub-a'), ('SIN_CONTESTAR', false));
      expect(await casaEnElMapa('ub-b'), ('SIN_CONTESTAR', true));
      final fila = await (db.select(
        db.houseStatuses,
      )..where((h) => h.ubicacionId.equals('ub-a'))).getSingle();
      expect(fila.createdBy, 'col-1', reason: 'el dueño de las casas, no un campo vacío');
      expect(
        [
          for (final c in encolador.encolados.where((c) => c.entidad == 'house_status'))
            c.operacion,
        ],
        [OperacionSync.delete, OperacionSync.insert],
      );
    });

    test('dado que ni A ni B tienen eventos, cuando se une, no se escribe ninguna fila de '
        '`house_status`', () async {
      await ubicacion('ub-a');
      await ubicacion('ub-b', lat: -34.9001);
      await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
      await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');

      await unirBAEnA();

      expect(await db.select(db.houseStatuses).get(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });
  });

  group('Escenario: Unir tipos - A casa y B edificio', () {
    test('dado que A es una casa y B un edificio con visitas en sus deptos, cuando se une, los '
        'deptos pasan con todo lo suyo y A, ya edificio, se recalcula con su tipo nuevo', () async {
      await ubicacion('ub-a');
      await ubicacion('ub-b', tipo: 'EDIFICIO', lat: -34.9001);
      await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
      await sembrarEspacio(db, id: 'dep-1', ubicacionId: 'ub-b', numeroDepto: '1A');
      await sembrarEspacio(db, id: 'dep-2', ubicacionId: 'ub-b', numeroDepto: '2B');
      await sembrarVinculo(db, id: 'ep-1', espacioId: 'dep-1', personaId: 'per-1');
      await insertarVisita(
        db,
        visitaDe(
          'vis-1',
          espacio: 'dep-1',
          vinculo: 'ep-1',
          resultado: TipoResultadoVisita.entrevista,
        ),
      );

      await unirBAEnA();

      expect(await vinculos(), {
        'ep-1': 'dep-1',
      }, reason: 'el depto pasó entero: nada que repuntar');
      expect(await visitas(), {'vis-1': 'dep-1'});
      final espacios = {
        for (final e in await db.select(db.espacios).get()) e.id: (e.ubicacionId, e.deletedAt),
      };
      expect(espacios['dep-1'], ('ub-a', null));
      expect(espacios['dep-2'], ('ub-a', null));
      final fila = await (db.select(
        db.houseStatuses,
      )..where((h) => h.ubicacionId.equals('ub-a'))).getSingle();
      expect((fila.tipoUbicacion, fila.color), ('EDIFICIO', 'ENTREVISTA_SIN_VENTA'));
    });
  });

  group('Escenario: Si la unión local falla', () {
    test('dado que el recálculo del color falla, cuando se une, no cambia nada: B viva, lo suyo '
        'donde estaba y nada encolado', () async {
      await sembrarCasasConGente();
      final estado = HouseStatusUpdaterEspia()..fallarCon = StateError('disco');
      final falla = armar(estado: estado);

      final r = await falla(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.isLeft(), isTrue);
      expect(estado.llamadas, isNotEmpty, reason: 'llegó a recalcular y ahí se revirtió');
      expect(await vinculos(), {'ep-a1': 'esp-a', 'ep-b1': 'esp-b', 'ep-b2': 'esp-b'});
      expect(await visitas(), {'vis-b1': 'esp-b'});
      expect(await agendas(), {'ag-b1': 'esp-b'});
      expect(await espacioDeBaja('esp-b'), isFalse);
      final b = await (db.select(db.ubicaciones)..where((u) => u.id.equals('ub-b'))).getSingle();
      expect(b.deletedAt, isNull);
      expect(await db.select(db.auditLogLocal).get(), isEmpty);
      expect(marcador.encolados, isEmpty);
    });

    test('dado que el recálculo anda, cuando se une, se recalcula primero B (antes de la baja) y '
        'después A, con el dueño de las casas y el instante de la unión', () async {
      await sembrarCasasConGente();
      final estado = HouseStatusUpdaterEspia();

      await armar(estado: estado)(
        const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'),
      );

      expect(estado.llamadas, [
        (ubicacionId: 'ub-b', ahora: ahora, colportorId: 'col-1'),
        (ubicacionId: 'ub-a', ahora: ahora, colportorId: 'col-1'),
      ]);
    });

    test('dado que el trabajo «marcar como duplicado» no se puede encolar, cuando se une, el '
        'traspaso se revierte con todo lo demás', () async {
      await sembrarCasasConGente();
      marcador.fallarCon = StateError('sin motor');

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.isLeft(), isTrue);
      expect(await vinculos(), {'ep-a1': 'esp-a', 'ep-b1': 'esp-b', 'ep-b2': 'esp-b'});
      expect(await visitas(), {'vis-b1': 'esp-b'});
      expect(await agendas(), {'ag-b1': 'esp-b'});
      expect(await espacioDeBaja('esp-b'), isFalse);
      expect(await db.select(db.houseStatuses).get(), isEmpty);
    });
  });
}
