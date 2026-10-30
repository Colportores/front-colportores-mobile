// HU-VIS-002 (#508): la lectura de la agenda contra las tablas reales. «Agenda baja»: la agenda de
// una casa o un depto dados de baja se oculta y vuelve si se reactivan; con la persona de baja la cita
// sigue, sin nombre. «Rango filtro»: la campaña en curso, de la más nueva a la más vieja.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/consulta_agenda_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/replica_de_campanias.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ConsultaAgendaRepositoryDrift repo;

  final desde = DateTime.utc(2026, 10, 28);
  final hasta = DateTime.utc(2026, 11, 5);
  final hoy = DateTime(2026, 10, 28);

  Future<List<String>> ventana() async => [
    for (final i in await repo.observar(colportorId: 'col-1', desde: desde, hasta: hasta).first)
      i.agenda.id,
  ];

  Future<List<ItemAgenda>> campania() =>
      repo.observarCampania(colportorId: 'col-1', hoy: hoy).first;

  Future<void> agendar(
    String id,
    DateTime cuando, {
    String espacio = 'esp-1',
    String? vinculo = 'ep-1',
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
  }) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: espacio,
      espacioPersonaId: vinculo,
      tipo: TipoAgenda.entrevista,
      fechaProgramada: cuando,
      estado: estado,
      colportorId: colportor,
      auditoria: auditoriaDe(),
    ),
  );

  Future<void> bajaDeUbicacion(String id, {DateTime? cuando}) => (db.update(
    db.ubicaciones,
  )..where((u) => u.id.equals(id))).write(UbicacionesCompanion(deletedAt: Value(cuando)));

  Future<void> bajaDeEspacio(String id, {DateTime? cuando}) => (db.update(
    db.espacios,
  )..where((e) => e.id.equals(id))).write(EspaciosCompanion(deletedAt: Value(cuando)));

  Future<void> bajaDePersona(String id, {DateTime? cuando}) => (db.update(
    db.personas,
  )..where((p) => p.id.equals(id))).write(PersonasCompanion(deletedAt: Value(cuando)));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = ConsultaAgendaRepositoryDrift(db);
    await sembrarCasa(db);
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(
            id: 'per-1',
            nombre: 'Ana',
            apellido: const Value('Martínez'),
            createdAt: t0,
            updatedAt: t0,
          ),
        );
  });
  tearDown(() => db.close());

  group('Agenda baja', () {
    test('con la casa de baja la agenda no sale, y con la casa reactivada vuelve sola', () async {
      await agendar('age-1', DateTime.utc(2026, 10, 30, 12));
      expect(await ventana(), ['age-1']);

      await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 28, 9));
      expect(await ventana(), isEmpty);
      expect(await campania(), isEmpty);

      await bajaDeUbicacion('ub-1');
      expect(await ventana(), ['age-1']);
      expect((await campania()).map((i) => i.agenda.id), ['age-1']);
    });

    test('con el depto de baja la agenda no sale, y con el depto reactivado vuelve', () async {
      await sembrarUbicacion(db, id: 'ub-2', tipo: 'EDIFICIO');
      await sembrarEspacio(db, id: 'esp-3', ubicacionId: 'ub-2', numeroDepto: '4B');
      await sembrarEspacio(db, id: 'esp-4', ubicacionId: 'ub-2', numeroDepto: '5C');
      await agendar('del-4B', DateTime.utc(2026, 10, 30, 12), espacio: 'esp-3', vinculo: null);
      await agendar('del-5C', DateTime.utc(2026, 10, 30, 13), espacio: 'esp-4', vinculo: null);

      await bajaDeEspacio('esp-3', cuando: DateTime.utc(2026, 10, 28, 9));

      // Solo se oculta la del depto de baja: la del otro depto del mismo edificio sigue.
      expect(await ventana(), ['del-5C']);
      expect((await campania()).map((i) => i.agenda.id), ['del-5C']);

      await bajaDeEspacio('esp-3');
      expect(await ventana(), ['del-4B', 'del-5C']);
    });

    test('la agenda oculta queda guardada: no se borra, no se cancela, no cambia', () async {
      await agendar('age-1', DateTime.utc(2026, 10, 30, 12));
      await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 28, 9));
      await ventana();

      final fila = await (db.select(db.agendas)..where((a) => a.id.equals('age-1'))).getSingle();

      expect(fila.deletedAt, isNull);
      expect(fila.estado, EstadoAgenda.programada.codigo);
      expect(fila.updatedAt, t0);
    });

    test('con la persona de baja la cita sigue, sin nombre', () async {
      await agendar('age-1', DateTime.utc(2026, 10, 30, 12));
      expect(
        (await repo.observar(colportorId: 'col-1', desde: desde, hasta: hasta).first)
            .single
            .nombrePersona,
        'Ana Martínez',
      );

      await bajaDePersona('per-1', cuando: DateTime.utc(2026, 10, 28, 9));

      final item =
          (await repo.observar(colportorId: 'col-1', desde: desde, hasta: hasta).first).single;
      expect(item.agenda.id, 'age-1');
      expect(item.nombrePersona, isNull);
      expect(item.casa?.ubicacionId, 'ub-1');
      expect((await campania()).single.nombrePersona, isNull);

      await bajaDePersona('per-1');
      expect((await campania()).single.nombrePersona, 'Ana Martínez');
    });

    test(
      'dar de baja una casa vuelve a emitir la lista sin su agenda (conteos de los días)',
      () async {
        await agendar('age-1', DateTime.utc(2026, 10, 30, 12));
        await agendar('age-2', DateTime.utc(2026, 10, 30, 13), espacio: 'esp-que-no-llego');
        final emisiones = <List<String>>[];
        final sub = repo
            .observar(colportorId: 'col-1', desde: desde, hasta: hasta)
            .listen((l) => emisiones.add([for (final i in l) i.agenda.id]));
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(emisiones.last, ['age-1', 'age-2']);

        await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 28, 9));
        await pumpEventQueue();
        // La que apunta a un espacio que todavía no llegó no se esconde: no se sabe de qué casa es.
        expect(emisiones.last, ['age-2']);

        await bajaDeUbicacion('ub-1');
        await pumpEventQueue();
        expect(emisiones.last, ['age-1', 'age-2']);
      },
    );

    test('una atrasada de una casa de baja tampoco sale', () async {
      await agendar('atrasada', DateTime.utc(2026, 10, 20, 12));
      await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 28, 9));

      expect(await ventana(), isEmpty);
    });
  });

  group('Campaña en curso', () {
    Future<void> inscribir({
      String campania = 'cam-1',
      String inicio = '2026-10-01',
      String? fin = '2027-02-28',
      String usuario = 'col-1',
      bool campaniaDeBaja = false,
      bool inscripcionDeBaja = false,
    }) async {
      final replica = ReplicaDeCampanias(db);
      await replica.bajar({
        'campania': [
          filaCampania(campania, 'Verano', inicio: inicio, fin: fin, deBaja: campaniaDeBaja),
        ],
        'campania_colportor': [
          filaInscripcion(
            'ins-$campania',
            campania: campania,
            usuario: usuario,
            deBaja: inscripcionDeBaja,
          ),
        ],
      });
    }

    Future<List<String>> ids() async => [for (final i in await campania()) i.agenda.id];

    setUp(() async {
      await agendar('antes', DateTime.utc(2026, 9, 20, 12), estado: EstadoAgenda.cumplida);
      await agendar('inicio', DateTime(2026, 10, 1).toUtc(), estado: EstadoAgenda.cumplida);
      await agendar('hace-3-semanas', DateTime.utc(2026, 10, 7, 12), estado: EstadoAgenda.cumplida);
      await agendar('ayer', DateTime.utc(2026, 10, 27, 12), estado: EstadoAgenda.noCumplida);
      await agendar('hoy', DateTime.utc(2026, 10, 28, 15));
      await agendar('futura', DateTime.utc(2026, 12, 20, 12), estado: EstadoAgenda.cancelada);
      await agendar('despues', DateTime(2027, 3, 1).toUtc());
      await agendar('ajena', DateTime.utc(2026, 10, 10, 12), colportor: 'col-2');
    });

    test('trae la campaña entera, de la más nueva a la más vieja, de todos los estados', () async {
      await inscribir();

      expect(await ids(), ['futura', 'hoy', 'ayer', 'hace-3-semanas', 'inicio']);
    });

    test('el primer y el último día de la campaña entran, el anterior y el siguiente no', () async {
      await inscribir(inicio: '2026-10-01', fin: '2026-12-20');
      await agendar('ultimo-dia', DateTime(2026, 12, 20, 23, 59).toUtc());
      await agendar('dia-siguiente', DateTime(2026, 12, 21).toUtc());
      await agendar('ultimo-dia-anterior', DateTime(2026, 9, 30, 23, 59).toUtc());

      final lista = await ids();

      expect(lista, containsAll(['ultimo-dia', 'inicio', 'futura']));
      expect(lista, isNot(contains('dia-siguiente')));
      expect(lista, isNot(contains('ultimo-dia-anterior')));
      expect(lista, isNot(contains('despues')));
    });

    test('una campaña sin fecha de fin (permanente) no corta por arriba', () async {
      await inscribir(fin: null);

      expect(await ids(), contains('despues'));
      expect(await ids(), isNot(contains('antes')));
    });

    test('sin ninguna campaña en el teléfono no se recorta nada (solo las propias)', () async {
      expect(await ids(), [
        'despues',
        'futura',
        'hoy',
        'ayer',
        'hace-3-semanas',
        'inicio',
        'antes',
      ]);
    });

    test(
      'una campaña terminada, por empezar, dada de baja o ajena no cuenta como la del curso',
      () async {
        await inscribir(campania: 'terminada', inicio: '2026-01-01', fin: '2026-10-27');
        await inscribir(campania: 'futura', inicio: '2026-11-01', fin: '2027-02-28');
        await inscribir(campania: 'baja', campaniaDeBaja: true);
        await inscribir(campania: 'sin-inscripcion', inscripcionDeBaja: true);
        await inscribir(campania: 'de-otro', usuario: 'col-2');

        // Ninguna está en curso para este colportor: queda abierto, como sin campaña.
        expect(await ids(), contains('antes'));
        expect(await ids(), contains('despues'));
      },
    );

    test(
      'con dos campañas en curso mira desde la que empezó primero hasta la que termina última',
      () async {
        await inscribir(campania: 'a', inicio: '2026-10-05', fin: '2026-11-30');
        await inscribir(campania: 'b', inicio: '2026-09-25', fin: '2026-10-31');

        final lista = await ids();

        expect(lista, contains('hace-3-semanas'));
        expect(lista, contains('inicio'));
        expect(lista, isNot(contains('antes')));
        expect(lista, isNot(contains('futura')));
      },
    );

    test('cambia sola cuando llega la campaña después del pull', () async {
      final emisiones = <List<String>>[];
      final sub = repo
          .observarCampania(colportorId: 'col-1', hoy: hoy)
          .listen((l) => emisiones.add([for (final i in l) i.agenda.id]));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emisiones.last, contains('antes'));

      await inscribir();
      await pumpEventQueue();

      expect(emisiones.last, ['futura', 'hoy', 'ayer', 'hace-3-semanas', 'inicio']);
    });

    test('vuelve a emitir cuando se cierra una agenda', () async {
      await inscribir();
      final emisiones = <List<ItemAgenda>>[];
      final sub = repo.observarCampania(colportorId: 'col-1', hoy: hoy).listen(emisiones.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await (db.update(db.agendas)..where((a) => a.id.equals('hoy'))).write(
        AgendasCompanion(estado: Value(EstadoAgenda.cumplida.codigo)),
      );
      await pumpEventQueue();

      expect(
        emisiones.last.firstWhere((i) => i.agenda.id == 'hoy').agenda.estado,
        EstadoAgenda.cumplida,
      );
    });

    test('cancelar la suscripción libera la lectura', () async {
      await inscribir();
      final sub = repo.observarCampania(colportorId: 'col-1', hoy: hoy).listen((_) {});
      await pumpEventQueue();

      await sub.cancel();

      // No queda nada escuchando: escribir no tira ni se cuelga.
      await agendar('otra', DateTime.utc(2026, 10, 29, 12));
      await pumpEventQueue();
    });
  });
}
