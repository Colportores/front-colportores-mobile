// HU-VIS-002: la lectura de la agenda contra las tablas reales (AppDatabase en memoria): el join con
// la persona y la dirección, la ventana de fechas y la reactividad.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/consulta_agenda_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ConsultaAgendaRepositoryDrift repo;

  // La ventana de los tests: del 28/10 (incluido) al 5/11 (excluido), en UTC.
  final desde = DateTime.utc(2026, 10, 28);
  final hasta = DateTime.utc(2026, 11, 5);

  Future<List<ItemAgenda>> leer({String colportorId = 'col-1'}) =>
      repo.observar(colportorId: colportorId, desde: desde, hasta: hasta).first;

  Future<void> agendar(
    String id,
    DateTime cuando, {
    String espacio = 'esp-1',
    String? vinculo = 'ep-1',
    TipoAgenda tipo = TipoAgenda.entrevista,
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
    String? alternativa,
    DateTime? borrada,
  }) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: espacio,
      espacioPersonaId: vinculo,
      tipo: tipo,
      fechaProgramada: cuando,
      ubicacionAltId: alternativa,
      estado: estado,
      colportorId: colportor,
      auditoria: auditoriaDe(borrada: borrada),
    ),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = ConsultaAgendaRepositoryDrift(db);
    await sembrarCasa(db);
    await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
      const UbicacionesCompanion(calle: Value('Av. Italia'), numero: Value('1234')),
    );
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

  test('trae la persona, la dirección y el depto de cada agenda', () async {
    await sembrarUbicacion(db, id: 'ub-2', tipo: 'EDIFICIO');
    await sembrarEspacio(db, id: 'esp-3', ubicacionId: 'ub-2', numeroDepto: '4B');
    await sembrarVinculo(db, id: 'ep-3', espacioId: 'esp-3', personaId: 'per-1');
    await agendar('age-1', DateTime.utc(2026, 10, 29, 12));
    await agendar('age-2', DateTime.utc(2026, 10, 30, 12), espacio: 'esp-3', vinculo: 'ep-3');

    final items = await leer();

    expect(items.map((i) => i.agenda.id), ['age-1', 'age-2']);
    expect(items[0].nombrePersona, 'Ana Martínez');
    expect(items[0].casa?.calle, 'Av. Italia');
    expect(items[0].casa?.numero, '1234');
    expect(items[0].casa?.tipo, TipoUbicacion.casa);
    expect(items[0].casa?.ubicacionId, 'ub-1');
    expect(items[1].numeroDepto, '4B');
    expect(items[1].casa?.tipo, TipoUbicacion.edificio);
  });

  test('la ventana incluye el primer instante y deja afuera el último', () async {
    await agendar('antes', desde.subtract(const Duration(milliseconds: 1)));
    await agendar('justo-desde', desde);
    await agendar('justo-antes-del-fin', hasta.subtract(const Duration(milliseconds: 1)));
    await agendar('justo-hasta', hasta);

    final items = await leer();

    expect(items.map((i) => i.agenda.id), ['justo-desde', 'justo-antes-del-fin']);
  });

  test('trae las agendas de todos los estados, para filtrar después en memoria', () async {
    for (final e in EstadoAgenda.values) {
      await agendar('age-${e.name}', DateTime.utc(2026, 10, 29, 12), estado: e);
    }

    final items = await leer();

    expect(items.map((i) => i.agenda.estado).toSet(), EstadoAgenda.values.toSet());
  });

  test('deja afuera las bajas y las agendas de otro colportor', () async {
    await agendar('mia', DateTime.utc(2026, 10, 29, 12));
    await agendar('baja', DateTime.utc(2026, 10, 29, 13), borrada: DateTime.utc(2026, 10, 25));
    await agendar('ajena', DateTime.utc(2026, 10, 29, 14), colportor: 'col-2');

    expect((await leer()).map((i) => i.agenda.id), ['mia']);
    expect((await leer(colportorId: 'col-2')).map((i) => i.agenda.id), ['ajena']);
  });

  test('ordena por hora y desempata por id', () async {
    await agendar('b', DateTime.utc(2026, 10, 29, 12));
    await agendar('a', DateTime.utc(2026, 10, 29, 12));
    await agendar('c', DateTime.utc(2026, 10, 28, 20));

    expect((await leer()).map((i) => i.agenda.id), ['c', 'a', 'b']);
  });

  test('la cobranza en otra dirección trae la dirección alternativa', () async {
    await sembrarUbicacion(db, id: 'ub-alt');
    await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-alt'))).write(
      const UbicacionesCompanion(calle: Value('Rivera'), numero: Value('77')),
    );
    await agendar(
      'age-1',
      DateTime.utc(2026, 10, 29, 12),
      tipo: TipoAgenda.cobranza,
      alternativa: 'ub-alt',
    );

    final item = (await leer()).single;

    expect(item.alternativa?.calle, 'Rivera');
    expect(item.casa?.calle, 'Av. Italia');
    expect(item.lugar?.calle, 'Rivera');
  });

  test('una agenda sin persona o con el espacio todavía sin bajar se muestra igual', () async {
    await agendar('sin-persona', DateTime.utc(2026, 10, 29, 12), vinculo: null);
    await agendar('huerfana', DateTime.utc(2026, 10, 29, 13), espacio: 'esp-que-no-llego');

    final items = await leer();

    expect(items.map((i) => i.agenda.id), ['sin-persona', 'huerfana']);
    expect(items[0].nombrePersona, isNull);
    expect(items[0].casa?.calle, 'Av. Italia');
    expect(items[1].casa, isNull);
    expect(items[1].numeroDepto, isNull);
  });

  test('vuelve a emitir cuando se agenda, se cancela o cambia la persona', () async {
    await agendar('age-1', DateTime.utc(2026, 10, 29, 12));
    final emisiones = <List<ItemAgenda>>[];
    final sub = repo
        .observar(colportorId: 'col-1', desde: desde, hasta: hasta)
        .listen(emisiones.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emisiones, hasLength(1));

    await agendar('age-2', DateTime.utc(2026, 10, 30, 12));
    await pumpEventQueue();
    expect(emisiones.last.map((i) => i.agenda.id), ['age-1', 'age-2']);

    await (db.update(db.agendas)..where((a) => a.id.equals('age-1'))).write(
      AgendasCompanion(estado: Value(EstadoAgenda.cancelada.codigo)),
    );
    await pumpEventQueue();
    expect(emisiones.last.first.agenda.estado, EstadoAgenda.cancelada);

    await (db.update(
      db.personas,
    )..where((p) => p.id.equals('per-1'))).write(const PersonasCompanion(nombre: Value('Beatriz')));
    await pumpEventQueue();
    expect(emisiones.last.first.nombrePersona, 'Beatriz Martínez');
  });
}
