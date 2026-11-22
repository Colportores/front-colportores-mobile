// «PRÓXIMA VISITA» de la ficha de la persona (23A·05, #405): la lectura de las visitas agendadas de una
// persona contra las tablas reales (AppDatabase en memoria): por todos sus vínculos, solo las
// programadas, sin lo de otra persona ni de otro colportor, sin la agenda de un depto de baja, y al día
// cuando algo cambia.
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ConsultaAgendaRepositoryDrift repo;

  Future<List<ItemAgenda>> leer({String colportorId = 'col-1', String personaId = 'per-1'}) =>
      repo.observarDeLaPersona(colportorId: colportorId, personaId: personaId).first;

  Future<void> agendar(
    String id,
    DateTime cuando, {
    String espacio = 'esp-1',
    String? vinculo = 'ep-1',
    TipoAgenda tipo = TipoAgenda.entrevista,
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
    DateTime? borrada,
  }) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: espacio,
      espacioPersonaId: vinculo,
      tipo: tipo,
      fechaProgramada: cuando,
      estado: estado,
      colportorId: colportor,
      auditoria: auditoriaDe(borrada: borrada),
    ),
  );

  Future<void> sembrarPersona(String id, String nombre) => db
      .into(db.personas)
      .insert(
        PersonasCompanion.insert(
          id: id,
          nombre: nombre,
          apellido: const Value('Pérez'),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = ConsultaAgendaRepositoryDrift(db);
    await sembrarCasa(db);
    await sembrarPersona('per-1', 'María');
    await sembrarPersona('per-2', 'Jorge');
  });
  tearDown(() => db.close());

  test('trae solo las programadas de la persona, de la más temprana a la más tardía', () async {
    await agendar('tarde', DateTime.utc(2026, 10, 30, 12));
    await agendar('temprano', DateTime.utc(2026, 10, 24, 12), tipo: TipoAgenda.cobranza);
    await agendar('cumplida', DateTime.utc(2026, 10, 20, 12), estado: EstadoAgenda.cumplida);
    await agendar('cancelada', DateTime.utc(2026, 10, 21, 12), estado: EstadoAgenda.cancelada);
    await agendar('no-cumplida', DateTime.utc(2026, 10, 22, 12), estado: EstadoAgenda.noCumplida);

    final items = await leer();

    expect(items.map((i) => i.agenda.id), ['temprano', 'tarde']);
    expect(items.first.nombrePersona, 'María Pérez');
    expect(items.first.agenda.tipo, TipoAgenda.cobranza);
  });

  test('no trae lo de otra persona, de otro colportor ni lo borrado', () async {
    await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
    await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
    await agendar('mia', DateTime.utc(2026, 10, 24, 12));
    await agendar('de-jorge', DateTime.utc(2026, 10, 24, 13), espacio: 'esp-2', vinculo: 'ep-2');
    await agendar('sin-persona', DateTime.utc(2026, 10, 24, 14), vinculo: null);
    await agendar('de-otro', DateTime.utc(2026, 10, 24, 15), colportor: 'col-2');
    await agendar('borrada', DateTime.utc(2026, 10, 24, 16), borrada: t0);

    expect((await leer()).map((i) => i.agenda.id), ['mia']);
    expect((await leer(personaId: 'per-2')).map((i) => i.agenda.id), ['de-jorge']);
    expect((await leer(colportorId: 'col-2')).map((i) => i.agenda.id), ['de-otro']);
    expect((await leer(personaId: 'no-existe')), isEmpty);
  });

  test(
    'trae las visitas por todos los vínculos de la persona, también el de un depto anterior',
    () async {
      await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
      await sembrarVinculo(db, id: 'ep-9', espacioId: 'esp-2', personaId: 'per-1');
      await agendar('en-1', DateTime.utc(2026, 10, 24, 12));
      await agendar('en-2', DateTime.utc(2026, 10, 25, 12), espacio: 'esp-2', vinculo: 'ep-9');

      expect((await leer()).map((i) => i.agenda.id), ['en-1', 'en-2']);
    },
  );

  test('con el depto dado de baja la agenda se oculta y vuelve sola si se reactiva', () async {
    await agendar('a1', DateTime.utc(2026, 10, 24, 12));
    await (db.update(
      db.espacios,
    )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0)));
    expect(await leer(), isEmpty);

    await (db.update(
      db.espacios,
    )..where((e) => e.id.equals('esp-1'))).write(const EspaciosCompanion(deletedAt: Value(null)));
    expect((await leer()).map((i) => i.agenda.id), ['a1']);
  });

  test('con la persona de baja la visita se lee igual, sin nombre', () async {
    await agendar('a1', DateTime.utc(2026, 10, 24, 12));
    await (db.update(
      db.personas,
    )..where((p) => p.id.equals('per-1'))).write(PersonasCompanion(deletedAt: Value(t0)));

    final items = await leer();

    expect(items.map((i) => i.agenda.id), ['a1']);
    expect(items.single.nombrePersona, isNull);
  });

  test('se vuelve a emitir al agendar y al cancelar, sin repetir lo que no cambió', () async {
    final emisiones = <List<String>>[];
    final suscripcion = repo
        .observarDeLaPersona(colportorId: 'col-1', personaId: 'per-1')
        .listen((l) => emisiones.add([for (final i in l) i.agenda.id]));
    addTearDown(suscripcion.cancel);

    Future<void> asentar() => Future<void>.delayed(const Duration(milliseconds: 50));
    await asentar();
    expect(emisiones.last, isEmpty);

    await agendar('a1', DateTime.utc(2026, 10, 24, 12));
    await asentar();
    expect(emisiones.last, ['a1']);

    // Una agenda de otra persona no cambia lo que se ve.
    await sembrarEspacio(db, id: 'esp-2');
    await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
    await agendar('a2', DateTime.utc(2026, 10, 24, 13), espacio: 'esp-2', vinculo: 'ep-2');
    await asentar();
    expect(emisiones.last, ['a1']);

    await (db.update(
      db.agendas,
    )..where((a) => a.id.equals('a1'))).write(const AgendasCompanion(estado: Value('CANCELADA')));
    await asentar();
    expect(emisiones.last, isEmpty);
  });
}
