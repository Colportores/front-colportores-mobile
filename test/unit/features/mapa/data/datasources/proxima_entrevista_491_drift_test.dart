// HU-VIS-002 (#491): `proximaEntrevista` de cada ubicación de la lista, desde la agenda local y contra
// las tablas reales (AppDatabase en memoria): la entrevista `PROGRAMADA` más cercana que todavía no
// pasó, de este colportor, en un espacio sin baja de la ubicación.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late UbicacionLocalDataSourceDrift local;
  var ahora = DateTime.utc(2026, 10, 28, 12);

  Future<void> ubicacion(String id, {String tipo = 'CASA', String creador = 'col-1'}) => db
      .into(db.ubicaciones)
      .insert(
        UbicacionesCompanion.insert(
          id: id,
          tipo: tipo,
          lat: -34.9,
          lon: -56.16,
          ciudadId: 'ciu-1',
          createdAt: t0,
          updatedAt: t0,
          createdBy: Value(creador),
        ),
      );

  Future<void> agendar(
    String id,
    DateTime cuando, {
    String espacio = 'esp-1',
    TipoAgenda tipo = TipoAgenda.entrevista,
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
    DateTime? borrada,
  }) => insertarAgenda(
    db,
    Agenda(
      id: id,
      espacioId: espacio,
      tipo: tipo,
      fechaProgramada: cuando,
      estado: estado,
      colportorId: colportor,
      auditoria: auditoriaDe(borrada: borrada),
    ),
  );

  Future<Map<String, DateTime?>> proximas() async => {
    for (final f in await local.observarListaDelColportor(colportorId: 'col-1').first)
      f.ubicacion.id: f.proximaEntrevista,
  };

  setUp(() async {
    ahora = DateTime.utc(2026, 10, 28, 12);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: EncoladorSyncEnMemoria(),
      ahora: () => ahora,
    );
    await ubicacion('ub-1');
    await sembrarEspacio(db);
  });
  tearDown(() => db.close());

  test('sin ninguna agenda no hay próxima entrevista', () async {
    expect(await proximas(), {'ub-1': null});
  });

  test('con una entrevista agendada, esa hora', () async {
    await agendar('a1', DateTime.utc(2026, 10, 30, 14, 30));

    expect(await proximas(), {'ub-1': DateTime.utc(2026, 10, 30, 14, 30)});
  });

  test('con varias, la más cercana en el tiempo', () async {
    await agendar('lejana', DateTime.utc(2026, 11, 20, 9));
    await agendar('cercana', DateTime.utc(2026, 10, 29, 16));
    await agendar('media', DateTime.utc(2026, 11, 2, 9));

    expect(await proximas(), {'ub-1': DateTime.utc(2026, 10, 29, 16)});
  });

  test('una que ya pasó no cuenta; la que viene después, sí', () async {
    await agendar('paso', DateTime.utc(2026, 10, 28, 11, 59));
    await agendar('viene', DateTime.utc(2026, 11, 1, 10));

    expect(await proximas(), {'ub-1': DateTime.utc(2026, 11, 1, 10)});
  });

  test('la que cae justo ahora todavía cuenta', () async {
    await agendar('ahora', ahora);

    expect(await proximas(), {'ub-1': ahora});
  });

  test(
    'una cobranza, o una agenda cerrada, cancelada o borrada, no es una próxima entrevista',
    () async {
      final cuando = DateTime.utc(2026, 10, 30, 14);
      await agendar('cobranza', cuando, tipo: TipoAgenda.cobranza);
      await agendar('cumplida', cuando, estado: EstadoAgenda.cumplida);
      await agendar('no-cumplida', cuando, estado: EstadoAgenda.noCumplida);
      await agendar('cancelada', cuando, estado: EstadoAgenda.cancelada);
      await agendar('borrada', cuando, borrada: DateTime.utc(2026, 10, 25));

      expect(await proximas(), {'ub-1': null});
    },
  );

  test('la agenda de otro colportor no cuenta', () async {
    await agendar('ajena', DateTime.utc(2026, 10, 30, 14), colportor: 'col-2');

    expect(await proximas(), {'ub-1': null});
  });

  test('en un edificio, la más cercana de cualquiera de sus deptos', () async {
    await ubicacion('ub-2', tipo: 'EDIFICIO');
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-2', numeroDepto: '1A');
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-2', numeroDepto: '2B');
    await agendar('en-a', DateTime.utc(2026, 11, 3, 9), espacio: 'esp-a');
    await agendar('en-b', DateTime.utc(2026, 10, 31, 9), espacio: 'esp-b');

    expect((await proximas())['ub-2'], DateTime.utc(2026, 10, 31, 9));
  });

  test('un depto dado de baja no aporta su agenda', () async {
    await ubicacion('ub-2', tipo: 'EDIFICIO');
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-2', numeroDepto: '1A');
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-2', numeroDepto: '2B');
    await agendar('en-a', DateTime.utc(2026, 11, 3, 9), espacio: 'esp-a');
    await agendar('en-b', DateTime.utc(2026, 10, 31, 9), espacio: 'esp-b');
    await (db.update(db.espacios)..where((e) => e.id.equals('esp-b'))).write(
      EspaciosCompanion(deletedAt: Value(DateTime.utc(2026, 10, 27))),
    );

    expect((await proximas())['ub-2'], DateTime.utc(2026, 11, 3, 9));
  });

  test('cada casa tiene la suya y la cantidad de espacios no se multiplica', () async {
    await ubicacion('ub-2', tipo: 'EDIFICIO');
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-2', numeroDepto: '1A');
    await sembrarEspacio(db, id: 'esp-b', ubicacionId: 'ub-2', numeroDepto: '2B');
    await agendar('x1', DateTime.utc(2026, 11, 3, 9));
    await agendar('x2', DateTime.utc(2026, 11, 4, 9), espacio: 'esp-a');
    await agendar('x3', DateTime.utc(2026, 11, 5, 9), espacio: 'esp-a');

    final filas = await local.observarListaDelColportor(colportorId: 'col-1').first;
    final porId = {for (final f in filas) f.ubicacion.id: f};

    expect(porId['ub-1']!.proximaEntrevista, DateTime.utc(2026, 11, 3, 9));
    expect(porId['ub-2']!.proximaEntrevista, DateTime.utc(2026, 11, 4, 9));
    expect(porId['ub-1']!.cantidadEspacios, 1);
    expect(porId['ub-2']!.cantidadEspacios, 2);
  });

  test('vuelve a emitir cuando se agenda, se cancela o se reprograma', () async {
    final emisiones = <DateTime?>[];
    final sub = local
        .observarListaDelColportor(colportorId: 'col-1')
        .listen((l) => emisiones.add(l.single.proximaEntrevista));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emisiones.last, isNull);

    await agendar('a1', DateTime.utc(2026, 10, 30, 14));
    await pumpEventQueue();
    expect(emisiones.last, DateTime.utc(2026, 10, 30, 14));

    await (db.update(db.agendas)..where((a) => a.id.equals('a1'))).write(
      AgendasCompanion(fechaProgramada: Value(DateTime.utc(2026, 10, 29, 9))),
    );
    await pumpEventQueue();
    expect(emisiones.last, DateTime.utc(2026, 10, 29, 9));

    await (db.update(db.agendas)..where((a) => a.id.equals('a1'))).write(
      AgendasCompanion(estado: Value(EstadoAgenda.cancelada.codigo)),
    );
    await pumpEventQueue();
    expect(emisiones.last, isNull);
  });
}
