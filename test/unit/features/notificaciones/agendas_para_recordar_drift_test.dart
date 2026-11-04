// HU-NOT-004 / issue #415 — qué agendas esperan su recordatorio, contra las tablas reales
// (AppDatabase en memoria): solo las programadas, sin baja, del colportor y con la visita en el
// futuro, con la dirección que va en el aviso.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/agendas_para_recordar_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late AgendasParaRecordarDrift agendas;
  final desde = DateTime.utc(2026, 10, 25, 10);

  Agenda agenda(
    String id, {
    DateTime? cuando,
    TipoAgenda tipo = TipoAgenda.entrevista,
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
    String espacio = 'esp-1',
    String? vinculo = 'ep-1',
    String? ubicacionAlt,
    DateTime? borrada,
  }) => Agenda(
    id: id,
    espacioId: espacio,
    espacioPersonaId: vinculo,
    tipo: tipo,
    fechaProgramada: cuando ?? DateTime.utc(2026, 10, 25, 14),
    ubicacionAltId: ubicacionAlt,
    estado: estado,
    colportorId: colportor,
    auditoria: auditoriaDe(borrada: borrada),
  );

  Future<void> direccion(String ubicacion, {String? calle, String? numero}) =>
      (db.update(db.ubicaciones)..where((u) => u.id.equals(ubicacion))).write(
        UbicacionesCompanion(calle: Value(calle), numero: Value(numero)),
      );

  Future<List<String>> ids({String colportor = 'col-1'}) async => [
    for (final r in await agendas.pendientes(colportorId: colportor, desde: desde)) r.agendaId,
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    agendas = AgendasParaRecordarDrift(db);
    await sembrarCasa(db);
    await direccion('ub-1', calle: 'Av. Italia', numero: '1234');
  });
  tearDown(() => db.close());

  test(
    'dado una agenda programada en el futuro, la devuelve con su tipo, su hora y la dirección',
    () async {
      await insertarAgenda(db, agenda('age-1', tipo: TipoAgenda.cobranza));

      final r = await agendas.pendientes(colportorId: 'col-1', desde: desde);

      expect(r, hasLength(1));
      expect(r.single.agendaId, 'age-1');
      expect(r.single.tipo, TipoAgenda.cobranza);
      expect(r.single.fechaProgramada, DateTime.utc(2026, 10, 25, 14));
      expect(r.single.direccion, 'Av. Italia 1234');
    },
  );

  test('dado agendas cumplidas, no cumplidas, canceladas o con baja, no las devuelve', () async {
    await insertarAgenda(db, agenda('programada'));
    await insertarAgenda(db, agenda('cumplida', estado: EstadoAgenda.cumplida));
    await insertarAgenda(db, agenda('no-cumplida', estado: EstadoAgenda.noCumplida));
    await insertarAgenda(db, agenda('cancelada', estado: EstadoAgenda.cancelada));
    await insertarAgenda(db, agenda('con-baja', borrada: t0));

    expect(await ids(), ['programada']);
  });

  test('dado una agenda de otro colportor, no la devuelve', () async {
    await insertarAgenda(db, agenda('mia'));
    await insertarAgenda(db, agenda('ajena', colportor: 'col-2'));

    expect(await ids(), ['mia']);
    expect(await ids(colportor: 'col-2'), ['ajena']);
  });

  test('dado una visita que ya pasó o es justo ahora, no la devuelve', () async {
    await insertarAgenda(db, agenda('pasada', cuando: DateTime.utc(2026, 10, 25, 9)));
    await insertarAgenda(db, agenda('ahora', cuando: desde));
    await insertarAgenda(db, agenda('futura', cuando: desde.add(const Duration(minutes: 1))));

    expect(await ids(), ['futura']);
  });

  test('dado varias, las devuelve de la más próxima a la más lejana', () async {
    await insertarAgenda(db, agenda('b', cuando: DateTime.utc(2026, 10, 25, 16)));
    await insertarAgenda(db, agenda('c', cuando: DateTime.utc(2026, 10, 26, 9)));
    await insertarAgenda(db, agenda('a', cuando: DateTime.utc(2026, 10, 25, 12)));

    expect(await ids(), ['a', 'b', 'c']);
  });

  test('dado una cobranza en otra dirección, el aviso lleva la alternativa', () async {
    await sembrarUbicacion(db, id: 'ub-2');
    await direccion('ub-2', calle: 'Mataojo', numero: '2044');
    await insertarAgenda(db, agenda('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-2'));

    final r = await agendas.pendientes(colportorId: 'col-1', desde: desde);

    expect(r.single.direccion, 'Mataojo 2044');
  });

  test('dado que la ubicación alternativa no llegó al teléfono, usa la de la casa', () async {
    await insertarAgenda(
      db,
      agenda('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-que-no-esta'),
    );

    final r = await agendas.pendientes(colportorId: 'col-1', desde: desde);

    expect(r.single.direccion, 'Av. Italia 1234');
  });

  test(
    'dado una ubicación sin calle o sin número, la dirección es lo que haya; sin ninguno, vacía',
    () async {
      await insertarAgenda(db, agenda('age-1'));

      await direccion('ub-1', calle: 'Av. Italia');
      expect(
        (await agendas.pendientes(colportorId: 'col-1', desde: desde)).single.direccion,
        'Av. Italia',
      );

      await direccion('ub-1', numero: '1234');
      expect(
        (await agendas.pendientes(colportorId: 'col-1', desde: desde)).single.direccion,
        '1234',
      );

      await direccion('ub-1');
      expect(
        (await agendas.pendientes(colportorId: 'col-1', desde: desde)).single.direccion,
        isEmpty,
      );
    },
  );

  test(
    'dado que el espacio todavía no llegó al teléfono, la agenda se devuelve igual, sin dirección',
    () async {
      await insertarAgenda(db, agenda('age-1', espacio: 'esp-fantasma', vinculo: null));

      final r = await agendas.pendientes(colportorId: 'col-1', desde: desde);

      expect(r.single.agendaId, 'age-1');
      expect(r.single.direccion, isEmpty);
    },
  );

  test('dado que no hay agendas, devuelve una lista vacía', () async {
    expect(await ids(), isEmpty);
  });
}
