// El acompañamiento de la jornada sobre la DB local de verdad (HU-JOR-003, #146): la lista de
// coordinadores que bajó con la sincronización, los acompañantes de una jornada (varios) y lo que sube.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/acompaniamiento_repository_drift.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/acompaniante.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/tendencia_de_la_jornada.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AcompaniamientoRepositoryDrift repo;
  var siguiente = 0;

  setUp(() async {
    siguiente = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    repo = AcompaniamientoRepositoryDrift(
      db,
      encolador: encolador,
      generarId: () => 'ja-${++siguiente}',
      ahora: () => DateTime.utc(2026, 11, 20, 12),
      logger: loggerMudo(),
    );
    await sembrarJornada(db);
  });
  tearDown(() => db.close());

  Future<void> coordinador(
    String id,
    String usuario,
    String nombre,
    String apellido, {
    String campania = 'cam-1',
    DateTime? borrado,
  }) => db
      .into(db.campaniaCoordinadores)
      .insert(
        CampaniaCoordinadoresCompanion.insert(
          id: id,
          campaniaId: campania,
          usuarioId: usuario,
          nombre: nombre,
          apellido: apellido,
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrado),
        ),
      );

  Future<void> marcarFuera(String filaId, {bool confirmada = true}) => db
      .into(db.syncFueraDelArea)
      .insert(
        SyncFueraDelAreaCompanion.insert(
          entidad: 'campania_coordinador',
          filaId: filaId,
          confirmada: confirmada,
        ),
      );

  group('la lista de «¿Quién te acompaña?»', () {
    test('trae los coordinadores de la campaña con nombre y apellido, ordenados', () async {
      await coordinador('c1', 'u-daniel', 'Daniel', 'Ruiz');
      await coordinador('c2', 'u-marta', 'Marta', 'Pérez');
      await coordinador('c3', 'u-otra', 'Rosa', 'Gómez', campania: 'cam-2');

      final lista = await repo.observarLista(colportorId: 'col-1', campaniaIds: {'cam-1'}).first;

      expect([for (final c in lista) c.nombreCompleto], ['Daniel Ruiz', 'Marta Pérez']);
      expect([for (final c in lista) c.usuarioId], ['u-daniel', 'u-marta']);
    });

    test(
      'sin saber la campaña de la jornada ofrece los de todas, sin repetir a la misma persona',
      () async {
        await coordinador('c1', 'u-marta', 'Marta', 'Pérez');
        await coordinador('c2', 'u-marta', 'Marta', 'Pérez', campania: 'cam-2');
        await coordinador('c3', 'u-daniel', 'Daniel', 'Ruiz', campania: 'cam-2');

        final lista = await repo.observarLista(colportorId: 'col-1').first;

        expect([for (final c in lista) c.usuarioId], ['u-daniel', 'u-marta']);
      },
    );

    test(
      'no ofrece a la propia colportora, a los dados de baja ni a los que dejaron de contar',
      () async {
        await coordinador('c1', 'col-1', 'Lucía', 'Silva');
        await coordinador('c2', 'u-baja', 'Beto', 'Baja', borrado: t0);
        await coordinador('c3', 'u-fuera', 'Fausto', 'Fuera');
        await coordinador('c4', 'u-ok', 'Marta', 'Pérez');
        await marcarFuera('c3');

        final lista = await repo.observarLista(colportorId: 'col-1').first;

        expect([for (final c in lista) c.usuarioId], ['u-ok']);
      },
    );

    test(
      'una marca sin confirmar (a la espera de un area_reset) todavía no la saca de la lista',
      () async {
        await coordinador('c1', 'u-marta', 'Marta', 'Pérez');
        await marcarFuera('c1', confirmada: false);

        final lista = await repo.observarLista(colportorId: 'col-1').first;

        expect(lista, hasLength(1));
      },
    );

    test('es reactiva: sale y vuelve cuando el pull marca y desmarca al coordinador', () async {
      await coordinador('c1', 'u-marta', 'Marta', 'Pérez');
      final vistas = <List<String>>[];
      final suscripcion = repo
          .observarLista(colportorId: 'col-1')
          .listen((l) => vistas.add([for (final c in l) c.usuarioId]));
      await pumpEventQueue();

      await marcarFuera('c1');
      await pumpEventQueue();
      await db.delete(db.syncFueraDelArea).go();
      await pumpEventQueue();
      await suscripcion.cancel();

      expect(vistas, [
        ['u-marta'],
        <String>[],
        ['u-marta'],
      ]);
    });
  });

  group('guardar los acompañantes de la jornada', () {
    test(
      'cada acompañante es una fila que sube con la jornada (varios, decisión «Dos acomp.»)',
      () async {
        await coordinador('c1', 'u-marta', 'Marta', 'Pérez');
        await coordinador('c2', 'u-daniel', 'Daniel', 'Ruiz');

        final r = await repo.guardar(
          jornadaId: 'jor-1',
          colportorId: 'col-1',
          usuarioIds: {'u-marta', 'u-daniel'},
        );

        expect(r.isRight(), isTrue);
        final quienes = await repo.observarDe('jor-1').first;
        expect([for (final q in quienes) q.nombreCompleto], ['Daniel Ruiz', 'Marta Pérez']);
        expect(encolador.encolados, hasLength(2));
        for (final e in encolador.encolados) {
          expect(e.entidad, 'jornada_acompaniante');
          expect(e.operacion, OperacionSync.insert);
          expect(e.payload['jornada_id'], 'jor-1');
          expect(e.payload['deleted_at'], isNull);
          expect(e.payload['created_by'], 'col-1');
          // Las columnas del servidor no viajan.
          expect(e.payload.keys, isNot(contains('colportor_id')));
          expect(e.payload.keys, isNot(contains('cargado_por')));
        }
        expect(
          {for (final e in encolador.encolados) e.payload['acompaniante_id']},
          {'u-marta', 'u-daniel'},
        );
      },
    );

    test('repetir el mismo conjunto no escribe ni vuelve a subir nada', () async {
      await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: {'u-marta'});
      encolador.encolados.clear();

      final r = await repo.guardar(
        jornadaId: 'jor-1',
        colportorId: 'col-1',
        usuarioIds: {'u-marta'},
      );

      expect(r.isRight(), isTrue);
      expect(encolador.encolados, isEmpty);
      expect(await db.select(db.jornadaAcompaniantes).get(), hasLength(1));
    });

    test(
      'quitar a uno lo da de baja (no lo borra) y sube la baja; los demás no se tocan',
      () async {
        await repo.guardar(
          jornadaId: 'jor-1',
          colportorId: 'col-1',
          usuarioIds: {'u-marta', 'u-daniel'},
        );
        encolador.encolados.clear();

        await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: {'u-marta'});

        expect(encolador.encolados, hasLength(1));
        expect(encolador.encolados.single.operacion, OperacionSync.delete);
        expect(encolador.encolados.single.payload['acompaniante_id'], 'u-daniel');
        expect(encolador.encolados.single.payload['deleted_at'], isNotNull);
        final filas = await db.select(db.jornadaAcompaniantes).get();
        expect(filas, hasLength(2));
        expect(filas.where((f) => f.deletedAt != null).single.acompanianteId, 'u-daniel');
        expect([for (final q in await repo.observarDe('jor-1').first) q.usuarioId], ['u-marta']);
      },
    );

    test(
      '«Nadie me acompañó» da de baja a todos; volver a sumar a alguien es una fila nueva',
      () async {
        await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: {'u-marta'});
        await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: {});
        expect(await repo.observarDe('jor-1').first, isEmpty);

        await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: {'u-marta'});

        final filas = await db.select(db.jornadaAcompaniantes).get();
        expect(filas, hasLength(2));
        expect(filas.where((f) => f.deletedAt == null), hasLength(1));
      },
    );

    test(
      'una persona que ya no está en la lista de hoy sigue figurando con su nombre mientras exista la fila',
      () async {
        await coordinador('c1', 'u-marta', 'Marta', 'Pérez');
        await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: {'u-marta'});
        await marcarFuera('c1');

        final quienes = await repo.observarDe('jor-1').first;

        expect(
          quienes.single,
          const Acompaniante(usuarioId: 'u-marta', nombre: 'Marta', apellido: 'Pérez'),
        );
      },
    );

    test('sin el nombre en la lista no se inventa uno', () async {
      await repo.guardar(jornadaId: 'jor-1', colportorId: 'col-1', usuarioIds: {'u-x'});

      final quienes = await repo.observarDe('jor-1').first;

      expect(quienes.single.nombreCompleto, isNull);
    });

    test('si la cola falla, no queda nada a medias y vuelve el error', () async {
      encolador.fallarCon = StateError('cola rota');

      final r = await repo.guardar(
        jornadaId: 'jor-1',
        colportorId: 'col-1',
        usuarioIds: {'u-marta'},
      );

      expect(r.isLeft(), isTrue);
      expect(await db.select(db.jornadaAcompaniantes).get(), isEmpty);
    });

    test('una jornada que no está en el teléfono no guarda nada', () async {
      final r = await repo.guardar(
        jornadaId: 'otra',
        colportorId: 'col-1',
        usuarioIds: {'u-marta'},
      );

      expect(r.isLeft(), isTrue);
      expect(await db.select(db.jornadaAcompaniantes).get(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });
  });

  group('la tendencia contra la jornada anterior', () {
    const campania = (desde: '2026-11-01', hasta: '2026-11-30');

    Future<void> jornada(String id, DateTime inicio, DateTime? fin) => db
        .into(db.jornadas)
        .insert(
          JornadasCompanion.insert(
            id: id,
            colportorId: 'col-1',
            inicio: inicio,
            fin: Value(fin),
            createdAt: inicio,
            updatedAt: inicio,
          ),
        );

    Future<void> visita(String id, String espacio, DateTime cuando) => db
        .into(db.visitas)
        .insert(
          VisitasCompanion.insert(
            id: id,
            espacioId: espacio,
            fecha: cuando,
            tipoResultado: 'NO_CONTESTO',
            colportorId: 'col-1',
            createdAt: cuando,
            updatedAt: cuando,
          ),
        );

    Future<void> venta(String id, DateTime cuando, {DateTime? borrada}) => db
        .into(db.ventas)
        .insert(
          VentasCompanion.insert(
            id: id,
            espacioPersonaId: 'ep-1',
            numeroTalonario: id,
            montoTotal: 1000,
            fecha: cuando,
            colportorId: 'col-1',
            createdAt: cuando,
            updatedAt: cuando,
            deletedAt: Value(borrada),
          ),
        );

    final ayer = DateTime.utc(2026, 11, 19, 12);
    final hoy = DateTime.utc(2026, 11, 20, 12);

    setUp(() async {
      for (var i = 1; i <= 4; i++) {
        await sembrarUbicacion(db, id: 'ub-$i');
        await sembrarEspacio(db, id: 'esp-$i', ubicacionId: 'ub-$i');
      }
      await sembrarEspacio(db, id: 'esp-1b', ubicacionId: 'ub-1', numeroDepto: '2');
    });

    Future<TendenciaDeLaJornada?> leer(String id, DateTime inicio, DateTime? fin) => repo
        .observarTendencia(
          colportorId: 'col-1',
          jornadaId: id,
          inicio: inicio,
          fin: fin,
          campania: campania,
        )
        .first;

    test(
      'cuenta casas distintas (dos deptos de la misma casa son una) y ventas, y las compara',
      () async {
        await jornada('jor-ayer', ayer, ayer.add(const Duration(hours: 5)));
        await visita('v1', 'esp-1', ayer.add(const Duration(hours: 1)));
        await visita('v2', 'esp-2', ayer.add(const Duration(hours: 2)));
        await venta('ve1', ayer.add(const Duration(hours: 2)));
        await jornada('jor-hoy', hoy, null);
        await visita('v3', 'esp-1', hoy.add(const Duration(hours: 1)));
        await visita('v4', 'esp-1b', hoy.add(const Duration(hours: 2)));
        await visita('v5', 'esp-3', hoy.add(const Duration(hours: 3)));
        await visita('v6', 'esp-4', hoy.add(const Duration(hours: 4)));
        await venta('ve2', hoy.add(const Duration(hours: 3)));
        await venta('ve3', hoy.add(const Duration(hours: 4)));
        await venta('ve4', hoy.add(const Duration(hours: 4)), borrada: hoy);

        final t = (await leer('jor-hoy', hoy, null))!;

        expect((t.casasVisitadas, t.ventas), (3, 2));
        expect((t.casasVisitadasAntes, t.ventasAntes), (2, 1));
        expect((t.diferenciaDeCasas, t.diferenciaDeVentas), (1, 1));
        expect(t.esPrimera, isFalse);
      },
    );

    test(
      'sin una jornada cerrada antes en la misma campaña es la primera: sin tendencia',
      () async {
        await jornada('jor-hoy', hoy, null);
        await visita('v1', 'esp-1', hoy.add(const Duration(hours: 1)));

        final t = (await leer('jor-hoy', hoy, null))!;

        expect(t.esPrimera, isTrue);
        expect(t.casasVisitadas, 1);
        expect(t.diferenciaDeCasas, isNull);
      },
    );

    test(
      'una jornada de otra campaña, una sin cerrar y una de otra persona no cuentan como la anterior',
      () async {
        await jornada('jor-vieja', DateTime.utc(2026, 10, 15, 12), DateTime.utc(2026, 10, 15, 18));
        await jornada('jor-abierta', ayer, null);
        await jornada('jor-hoy', hoy, null);

        final t = (await leer('jor-hoy', hoy, null))!;

        expect(t.esPrimera, isTrue);
      },
    );

    test(
      'con la campaña desconocida no hay tendencia (no se afirma una «primera jornada»)',
      () async {
        await jornada('jor-hoy', hoy, null);

        final t = await repo
            .observarTendencia(colportorId: 'col-1', jornadaId: 'jor-hoy', inicio: hoy)
            .first;

        expect(t, isNull);
      },
    );

    test('cambia sola cuando la colportora visita otra casa', () async {
      await jornada('jor-hoy', hoy, null);
      final casas = <int>[];
      final suscripcion = repo
          .observarTendencia(
            colportorId: 'col-1',
            jornadaId: 'jor-hoy',
            inicio: hoy,
            campania: campania,
          )
          .listen((t) => casas.add(t!.casasVisitadas));
      await pumpEventQueue();

      await visita('v1', 'esp-1', hoy.add(const Duration(hours: 1)));
      await pumpEventQueue();
      await suscripcion.cancel();

      expect(casas, [0, 1]);
    });
  });
}
