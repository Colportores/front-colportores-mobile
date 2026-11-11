// La unión de duplicados que el servidor rechaza (HU-UBI-006, #679; decisión de Cristian, 10/11, «Unión
// rech.»: «queda separado en el teléfono»). Contra la DB real en memoria: la unión guarda qué movió y,
// cuando su trabajo «marcar como duplicado» vuelve `INVALID`, una transacción la deshace sin borrar
// nada, y el par vuelve a «Posibles duplicados» con el código del rechazo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/sync_queue_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/pares_duplicados_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/uniones_locales_table.dart';
import 'package:colportores_mobile/features/mapa/data/models/movimientos_de_union.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_baja.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart' hide t0;
import '../../../../../helpers/duplicados_falsos.dart' show EncoladorMarcarDuplicadoFalso;
import '../../../../../helpers/logger_mudo.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 13, 45, 10, 123);
  final tUnion = DateTime.utc(2026, 11, 2, 9, 0, 0, 250);
  final tDeshacer = DateTime.utc(2026, 11, 2, 10);

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late HouseStatusUpdaterEspia casas;
  late EncoladorMarcarDuplicadoFalso marcar;
  late UbicacionLocalDataSourceDrift local;

  UbicacionModel ubicacion(String id, {TipoUbicacion tipo = TipoUbicacion.casa}) => UbicacionModel(
    id: id,
    tipo: tipo,
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
    casas = HouseStatusUpdaterEspia();
    marcar = EncoladorMarcarDuplicadoFalso();
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: marcar,
      estadoDeLasCasas: casas,
    );
  });
  tearDown(() => db.close());

  /// El trabajo de la unión en la cola, como lo deja el motor: el falso devuelve `trabajo-N` y acá se
  /// escribe la fila de `sync_queue` con ese `id`, en el estado [estado].
  Future<void> trabajo(String id, {String estado = EstadoJob.pending, String codigo = ''}) => db
      .into(db.syncQueue)
      .insertOnConflictUpdate(
        SyncQueueCompanion.insert(
          id: id,
          clientOpId: 'op-$id',
          entity: 'ubicacion',
          op: 'marcar_como_duplicado',
          payload: '{}',
          rowPk: const Value('ub-b'),
          createdAt: tUnion,
          state: estado,
          code: Value(codigo),
        ),
      );

  Future<void> rechazar(String id, String codigo) =>
      trabajo(id, estado: EstadoJob.invalid, codigo: codigo);

  Future<UbicacionFila> fila(String id) =>
      (db.select(db.ubicaciones)..where((u) => u.id.equals(id))).getSingle();
  Future<EspacioFila> espacio(String id) =>
      (db.select(db.espacios)..where((e) => e.id.equals(id))).getSingle();
  Future<String> espacioDelVinculo(String id) async =>
      (await (db.select(db.espacioPersonas)..where((e) => e.id.equals(id))).getSingle()).espacioId;
  Future<String> espacioDeLaVisita(String id) async =>
      (await (db.select(db.visitas)..where((e) => e.id.equals(id))).getSingle()).espacioId;
  Future<AgendaFila> agenda(String id) =>
      (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle();
  Future<UnionLocalFila> union(String trabajoId) =>
      (db.select(db.unionesLocales)..where((u) => u.trabajoId.equals(trabajoId))).getSingle();

  Future<void> nota(String id, String ubicacionId) => db
      .into(db.notas)
      .insert(
        NotasCompanion.insert(
          id: id,
          targetType: TipoObjetivoNota.ubicacion,
          targetId: ubicacionId,
          texto: 'Atiende de tarde',
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  /// A: casa con su espacio único `esp-a`. B: casa con su único `esp-b` (con la persona `ep-b`, una
  /// visita y una entrevista), y un depto `esp-b2`.
  Future<void> sembrarPar() async {
    await local.insertar(ubicacion('ub-a'));
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
    await local.insertar(ubicacion('ub-b'));
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-b');
    await sembrarEspacio(db, id: 'esp-b2', ubicacionId: 'ub-b', numeroDepto: '2B');
    await sembrarVinculo(db, id: 'ep-b', espacioId: 'esp-b', personaId: 'per-b');
    await insertarVisita(db, visitaDe('vis-b', espacio: 'esp-b', vinculo: 'ep-b'));
    await insertarAgenda(db, agendaDe('ag-b', espacio: 'esp-b', vinculo: 'ep-b'));
  }

  group('la unión guarda qué movió', () {
    test('dado un par con espacio único, depto, persona, alternativas y notas, cuando se une, '
        'queda una fila APLICADA con el id del trabajo y los ids de todo lo que movió', () async {
      await sembrarPar();
      // Otra casa (ub-c) con una entrevista y un vínculo que nombran a B como casa alternativa.
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
      await nota('nota-b', 'ub-b');

      final r = await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);

      expect(r.escribio, isTrue);
      final u = await union('trabajo-1');
      expect(u.conservadaId, 'ub-a');
      expect(u.duplicadaId, 'ub-b');
      expect(u.estado, EstadoUnionLocal.aplicada);
      expect(u.codigoRechazo, isNull);
      final m = MovimientosDeUnion.decodificar(u.movimientos);
      expect(m.espaciosPasados, ['esp-b2']);
      expect(m.espaciosFundidos.single.toJson(), {
        'espacio_id': 'esp-b',
        'unico_de_a': 'esp-a',
        'vinculos': ['ep-b'],
        'visitas': ['vis-b'],
        'agendas': ['ag-b'],
      });
      expect(m.agendasAlternativas, ['ag-c']);
      expect(m.vinculosAlternativos, ['ep-c']);
      expect(m.notasDelLugar, ['nota-b']);
      expect(m.duplicadaDadaDeBaja, isTrue);
      expect(m.conservadaPasoAEdificio, isTrue, reason: 'A queda con esp-a y el depto 2B');
    });

    test('dado que el trabajo no se pudo encolar, cuando la unión se revierte, tampoco queda su '
        'fila: la unión y lo que movió van juntos', () async {
      await sembrarPar();
      marcar.fallarCon = StateError('sin motor');

      await expectLater(local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion), throwsStateError);

      expect(await db.select(db.unionesLocales).get(), isEmpty);
    });
  });

  group('cuando el servidor rechaza el trabajo', () {
    test(
      'dado una unión con todo, cuando su trabajo vuelve UB003, se deshace entera: espacios, lo '
      'que colgaba del único, alternativas, notas, B viva y A otra vez casa, sin borrar nada',
      () async {
        await sembrarPar();
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
        await nota('nota-b', 'ub-b');
        await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
        await rechazar('trabajo-1', 'UB003');
        encolador.encolados.clear();
        casas.llamadas.clear();

        final hechas = await local.deshacerUnionesRechazadas(ahora: tDeshacer);

        expect(hechas, hasLength(1));
        expect(hechas.single.codigo, 'UB003');
        expect(hechas.single.duplicadaReactivada, isTrue);
        expect(hechas.single.conservadaVolvioACasa, isTrue);
        expect(hechas.single.sinVolver, 0);
        // Los espacios.
        expect((await espacio('esp-b2')).ubicacionId, 'ub-b');
        expect((await espacio('esp-b')).deletedAt, isNull, reason: 'el único fundido se reactiva');
        expect((await espacio('esp-b')).ubicacionId, 'ub-b');
        expect((await espacio('esp-a')).ubicacionId, 'ub-a');
        // Lo que colgaba del único de B.
        expect(await espacioDelVinculo('ep-b'), 'esp-b');
        expect(await espacioDeLaVisita('vis-b'), 'esp-b');
        expect((await agenda('ag-b')).espacioId, 'esp-b');
        // Alternativas y notas.
        expect((await agenda('ag-c')).ubicacionAltId, 'ub-b');
        final epC = await (db.select(
          db.espacioPersonas,
        )..where((e) => e.id.equals('ep-c'))).getSingle();
        expect(epC.ubicacionCobranzaAltId, 'ub-b');
        final notaB = await (db.select(db.notas)..where((n) => n.id.equals('nota-b'))).getSingle();
        expect(notaB.targetId, 'ub-b');
        // B viva y A casa, con su update encolado (lo único que se encola).
        expect((await fila('ub-b')).deletedAt, isNull);
        expect((await fila('ub-a')).tipo, 'CASA');
        expect(
          encolador.encolados.map((c) => '${c.entidad}:${c.operacion.name}:${c.payload['id']}'),
          ['ubicacion:update:ub-a'],
        );
        expect(encolador.encolados.single.payload['tipo'], 'CASA');
        // El color de las dos se recalcula.
        expect(casas.llamadas.map((l) => l.ubicacionId), ['ub-a', 'ub-b']);
        // La unión queda deshecha con su código; el trabajo sigue INVALID.
        final u = await union('trabajo-1');
        expect(u.estado, EstadoUnionLocal.deshecha);
        expect(u.codigoRechazo, 'UB003');
        expect(u.deshechaEn, tDeshacer);
        final q = await (db.select(
          db.syncQueue,
        )..where((q) => q.id.equals('trabajo-1'))).getSingle();
        expect(q.state, EstadoJob.invalid);
        // Nada se borró.
        expect(await db.select(db.espacios).get(), hasLength(4));
        expect(await db.select(db.espacioPersonas).get(), hasLength(2));
      },
    );

    test('dado B separada de nuevo, la marca duplicado_de_A deja de contar: se puede dar de baja y '
        'reactivar como cualquiera, y la Lista no muestra «Unida a otra ubicación»', () async {
      await sembrarPar();
      await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
      await rechazar('trabajo-1', '42501');
      await local.deshacerUnionesRechazadas(ahora: tDeshacer);

      final viva = await fila('ub-b');
      final tBaja = DateTime.utc(2026, 11, 3, 9);
      await local.cambiarBaja(
        'ub-b',
        baseUpdatedAt: viva.updatedAt,
        updatedAt: tBaja,
        deletedAt: tBaja,
      );
      final lista = await local
          .observarListaDelColportor(colportorId: 'col-1', incluirBajas: true)
          .first;
      final b = lista.firstWhere((u) => u.ubicacion.id == 'ub-b');
      expect(MotivosBaja.esUnion(b.motivoBaja), isFalse);

      final tAlta = DateTime.utc(2026, 11, 3, 10);
      final r = await local.cambiarBaja(
        'ub-b',
        baseUpdatedAt: tBaja,
        updatedAt: tAlta,
        deletedAt: null,
      );
      expect(r.escribio, isTrue, reason: 'no la frena la guarda de las bajas por unión');
      final eventos = await (db.select(
        db.auditLogLocal,
      )..where((a) => a.uuid.equals('ub-b'))).get();
      expect(eventos.map((e) => e.evento), contains(EventoAuditoriaLocal.ubicacionUnionDeshecha));
    });

    test(
      'dado una unión cuyo trabajo sigue PENDING, DONE o IN_FLIGHT, no se deshace nada',
      () async {
        await sembrarPar();
        await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);

        for (final estado in [EstadoJob.pending, EstadoJob.inFlight, EstadoJob.done]) {
          await trabajo('trabajo-1', estado: estado);
          expect(await local.deshacerUnionesRechazadas(ahora: tDeshacer), isEmpty, reason: estado);
        }
        expect((await fila('ub-b')).deletedAt, isNotNull);
        expect((await union('trabajo-1')).estado, EstadoUnionLocal.aplicada);
      },
    );

    test(
      'dado una unión ya deshecha, cuando se vuelve a llamar (dos avisos seguidos), no hace nada '
      'de más',
      () async {
        await sembrarPar();
        await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
        await rechazar('trabajo-1', 'UB003');
        encolador.encolados.clear();

        final [primera, segunda] = await Future.wait([
          local.deshacerUnionesRechazadas(ahora: tDeshacer),
          local.deshacerUnionesRechazadas(ahora: tDeshacer),
        ]);

        expect(primera.length + segunda.length, 1);
        expect(await local.deshacerUnionesRechazadas(ahora: tDeshacer), isEmpty);
        expect(encolador.encolados.where((c) => c.payload['tipo'] == 'CASA'), hasLength(1));
      },
    );

    test(
      'dado el par unido dos veces (la primera rechazada y deshecha, la segunda vigente), cuando '
      'vuelve otro aviso del primer trabajo, la segunda unión no se toca',
      () async {
        await sembrarPar();
        await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
        await rechazar('trabajo-1', 'CG001');
        await local.deshacerUnionesRechazadas(ahora: tDeshacer);
        await local.unirDuplicada('ub-a', 'ub-b', ahora: DateTime.utc(2026, 11, 2, 11));
        await trabajo('trabajo-2');

        expect(
          await local.deshacerUnionesRechazadas(ahora: DateTime.utc(2026, 11, 2, 12)),
          isEmpty,
        );
        expect((await fila('ub-b')).deletedAt, isNotNull, reason: 'la segunda unión sigue en pie');
        expect((await union('trabajo-2')).estado, EstadoUnionLocal.aplicada);
      },
    );

    test(
      'dado que después de unir se cargó un depto en A, cuando se deshace, el depto queda en A y '
      'A sigue edificio (lo creado después queda donde se creó)',
      () async {
        await sembrarPar();
        await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
        await sembrarEspacio(db, id: 'esp-a2', ubicacionId: 'ub-a', numeroDepto: '3C');
        await rechazar('trabajo-1', 'UB003');
        encolador.encolados.clear();

        final [hecha] = await local.deshacerUnionesRechazadas(ahora: tDeshacer);

        expect((await espacio('esp-a2')).ubicacionId, 'ub-a');
        expect((await espacio('esp-b2')).ubicacionId, 'ub-b');
        expect((await fila('ub-a')).tipo, 'EDIFICIO');
        expect(hecha.conservadaVolvioACasa, isFalse);
        expect(encolador.encolados.where((c) => c.entidad == 'ubicacion'), isEmpty);
      },
    );

    test(
      'dado que después A se unió a C y el depto de B pasó a C, cuando se deshace la primera, el '
      'depto se queda en C (ya no está donde lo dejó) y se cuenta como sin volver',
      () async {
        await sembrarPar();
        await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
        await local.insertar(ubicacion('ub-c', tipo: TipoUbicacion.edificio));
        await sembrarEspacio(db, id: 'esp-c', ubicacionId: 'ub-c', numeroDepto: '1A');
        await local.unirDuplicada('ub-c', 'ub-a', ahora: DateTime.utc(2026, 11, 2, 9, 30));
        await rechazar('trabajo-1', '42501');

        final [hecha] = await local.deshacerUnionesRechazadas(ahora: tDeshacer);

        expect((await espacio('esp-b2')).ubicacionId, 'ub-c');
        expect(hecha.sinVolver, greaterThan(0));
        expect(
          (await fila('ub-b')).deletedAt,
          isNull,
          reason: 'B igual vuelve: su baja era esta unión',
        );
        expect((await union('trabajo-2')).estado, EstadoUnionLocal.aplicada);
      },
    );

    test('dado que B ya estaba de baja y tenía espacios activos, cuando se deshace, sus espacios '
        'vuelven pero B sigue de baja (no la dio de baja esta unión)', () async {
      await local.insertar(ubicacion('ub-a', tipo: TipoUbicacion.edificio));
      await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a', numeroDepto: '1A');
      await sembrarUbicacion(db, id: 'ub-b', borrada: t0);
      await sembrarEspacio(db, id: 'esp-b2', ubicacionId: 'ub-b', numeroDepto: '2B');
      await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
      await rechazar('trabajo-1', 'UB004');

      final [hecha] = await local.deshacerUnionesRechazadas(ahora: tDeshacer);

      expect((await espacio('esp-b2')).ubicacionId, 'ub-b');
      expect(hecha.duplicadaReactivada, isFalse);
      expect((await fila('ub-b')).deletedAt, t0);
    });

    test(
      'dado una falla a mitad de deshacer, no queda nada a medias y se puede reintentar',
      () async {
        await sembrarPar();
        await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
        await rechazar('trabajo-1', 'UB003');
        casas.fallarCon = StateError('disco');

        await expectLater(local.deshacerUnionesRechazadas(ahora: tDeshacer), throwsStateError);

        expect((await espacio('esp-b2')).ubicacionId, 'ub-a', reason: 'la transacción se revirtió');
        expect((await fila('ub-b')).deletedAt, isNotNull);
        expect((await union('trabajo-1')).estado, EstadoUnionLocal.aplicada);

        casas.fallarCon = null;
        expect(await local.deshacerUnionesRechazadas(ahora: tDeshacer), hasLength(1));
        expect((await espacio('esp-b2')).ubicacionId, 'ub-b');
      },
    );

    test('observarUnionesPorDeshacer avisa cuando el trabajo vuelve INVALID y vuelve a 0 al '
        'deshacerla', () async {
      await sembrarPar();
      await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
      await trabajo('trabajo-1');
      final valores = <int>[];
      final sub = local.observarUnionesPorDeshacer().listen(valores.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await rechazar('trabajo-1', 'UB003');
      await pumpEventQueue();
      await local.deshacerUnionesRechazadas(ahora: tDeshacer);
      await pumpEventQueue();

      expect(valores, [0, 1, 0]);
    });
  });

  group('el aviso del par (vista 10)', () {
    test('la última unión de cada par manda: rechazada y deshecha da su código; unida de nuevo, ya '
        'no hay aviso', () async {
      final pares = ParesDuplicadosLocalDataSourceDrift(db);
      await sembrarPar();
      await local.unirDuplicada('ub-a', 'ub-b', ahora: tUnion);
      await rechazar('trabajo-1', 'UB003');

      expect(
        await pares.observarUnionesRechazadas().first,
        isEmpty,
        reason: 'todavía no se deshizo',
      );

      await local.deshacerUnionesRechazadas(ahora: tDeshacer);
      expect(await pares.observarUnionesRechazadas().first, {
        ParDuplicado.claveDe('ub-a', 'ub-b'): 'UB003',
      });

      await local.unirDuplicada('ub-b', 'ub-a', ahora: DateTime.utc(2026, 11, 2, 11));
      expect(await pares.observarUnionesRechazadas().first, isEmpty);
    });
  });
}
