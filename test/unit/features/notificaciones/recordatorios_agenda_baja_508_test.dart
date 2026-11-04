// HU-VIS-002 (#508, «Agenda baja», regla R7): mientras la agenda está oculta —su casa o su depto están
// de baja— tampoco suena su recordatorio; si se reactiva, vuelve con la agenda. Contra las tablas
// reales (AppDatabase en memoria) y contra el conciliador.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/agendas_para_recordar_drift.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/preferencias_recordatorios_repository.dart';
import 'package:colportores_mobile/features/notificaciones/domain/services/conciliador_recordatorios_ocultos.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

RecordatorioDeVisita _visita(String id) => RecordatorioDeVisita(
  agendaId: id,
  tipo: TipoAgenda.entrevista,
  direccion: 'Av. Italia 1234',
  fechaProgramada: DateTime.utc(2026, 10, 30, 14),
);

AgendaConAviso _a(String id, {bool oculta = false}) => (visita: _visita(id), oculta: oculta);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('ConciliadorRecordatoriosOcultos', () {
    late RecordatoriosEnMemoria recordatorios;
    late ConciliadorRecordatoriosOcultos conciliador;

    setUp(() {
      recordatorios = RecordatoriosEnMemoria();
      conciliador = ConciliadorRecordatoriosOcultos(recordatorios);
    });

    test('lo que no está oculto no se toca, ni la primera vez ni las siguientes', () async {
      await conciliador.aplicar([_a('a'), _a('b')]);
      await conciliador.aplicar([_a('a'), _a('b'), _a('c')]);

      expect(recordatorios.llamadas, isEmpty);
    });

    test('la agenda que pasa a oculta pierde su aviso una sola vez', () async {
      await conciliador.aplicar([_a('a'), _a('b')]);
      await conciliador.aplicar([_a('a', oculta: true), _a('b')]);
      await conciliador.aplicar([_a('a', oculta: true), _a('b')]);

      expect(recordatorios.llamadas, ['cancelar:a']);
    });

    test('la que ya estaba oculta al abrir la app también pierde el aviso', () async {
      await conciliador.aplicar([_a('a', oculta: true), _a('b')]);

      expect(recordatorios.llamadas, ['cancelar:a']);
    });

    test('al reactivar la casa el aviso vuelve con los datos de la visita', () async {
      await conciliador.aplicar([_a('a')]);
      await conciliador.aplicar([_a('a', oculta: true)]);
      await conciliador.aplicar([_a('a')]);

      expect(recordatorios.llamadas, ['cancelar:a', 'programar:a']);
      expect(recordatorios.programados['a'], _visita('a'));
    });

    test('ocultar, reactivar y volver a ocultar sigue el orden de las lecturas', () async {
      await conciliador.aplicar([_a('a')]);
      // Sin esperar a cada una: las lecturas llegan seguidas y no se pisan.
      final todas = [
        conciliador.aplicar([_a('a', oculta: true)]),
        conciliador.aplicar([_a('a')]),
        conciliador.aplicar([_a('a', oculta: true)]),
      ];
      await Future.wait(todas);

      expect(recordatorios.llamadas, ['cancelar:a', 'programar:a', 'cancelar:a']);
      expect(recordatorios.programados, isEmpty);
    });

    test('una agenda que sale de la lista (se cumplió o se canceló) se olvida', () async {
      await conciliador.aplicar([_a('a', oculta: true)]);
      await conciliador.aplicar([]);
      await conciliador.aplicar([_a('a')]);

      // Volvió como una nueva y visible: no es una reactivación.
      expect(recordatorios.llamadas, ['cancelar:a']);
    });

    test('si el teléfono no puede cancelar o programar, sigue con las demás', () async {
      recordatorios.puedeCancelar = false;

      await conciliador.aplicar([_a('a', oculta: true), _a('b', oculta: true)]);

      expect(recordatorios.llamadas, ['cancelar:a', 'cancelar:b']);
    });
  });

  group('AgendasParaRecordarDrift con casas de baja', () {
    late AppDatabase db;
    late AgendasParaRecordarDrift fuente;
    final desde = DateTime.utc(2026, 10, 25, 10);

    Future<void> agendar(String id, {String espacio = 'esp-1', DateTime? cuando}) => insertarAgenda(
      db,
      Agenda(
        id: id,
        espacioId: espacio,
        espacioPersonaId: null,
        tipo: TipoAgenda.entrevista,
        fechaProgramada: cuando ?? DateTime.utc(2026, 10, 30, 14),
        estado: EstadoAgenda.programada,
        colportorId: 'col-1',
        auditoria: auditoriaDe(creada: DateTime.utc(2026, 10, 1)),
      ),
    );

    Future<void> bajaDeUbicacion(String id, {DateTime? cuando}) => (db.update(
      db.ubicaciones,
    )..where((u) => u.id.equals(id))).write(UbicacionesCompanion(deletedAt: Value(cuando)));

    Future<void> bajaDeEspacio(String id, {DateTime? cuando}) => (db.update(
      db.espacios,
    )..where((e) => e.id.equals(id))).write(EspaciosCompanion(deletedAt: Value(cuando)));

    Future<List<String>> pendientes() async => [
      for (final r in await fuente.pendientes(colportorId: 'col-1', desde: desde)) r.agendaId,
    ];

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      fuente = AgendasParaRecordarDrift(db);
      await sembrarCasa(db);
    });
    tearDown(() => db.close());

    test(
      'la agenda de una casa de baja no se reprograma, y con la casa reactivada vuelve',
      () async {
        await agendar('age-1');
        expect(await pendientes(), ['age-1']);

        await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 25));
        expect(await pendientes(), isEmpty);

        await bajaDeUbicacion('ub-1');
        expect(await pendientes(), ['age-1']);
      },
    );

    test('lo mismo con el depto de baja, sin tocar los otros deptos', () async {
      await sembrarUbicacion(db, id: 'ub-2', tipo: 'EDIFICIO');
      await sembrarEspacio(db, id: 'esp-3', ubicacionId: 'ub-2', numeroDepto: '4B');
      await sembrarEspacio(db, id: 'esp-4', ubicacionId: 'ub-2', numeroDepto: '5C');
      await agendar('del-4B', espacio: 'esp-3');
      await agendar('del-5C', espacio: 'esp-4');

      await bajaDeEspacio('esp-3', cuando: DateTime.utc(2026, 10, 25));

      expect(await pendientes(), ['del-5C']);
    });

    test('la agenda oculta no cuenta como un aviso que sonó', () async {
      await agendar('age-1', cuando: DateTime.utc(2026, 10, 26, 14));
      await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 25));

      final sonaron = await fuente.conAvisoEntre(
        colportorId: 'col-1',
        desde: DateTime.utc(2026, 10, 26),
        hasta: DateTime.utc(2026, 10, 27),
        anticipacionMinutos: 30,
      );

      expect(sonaron, isEmpty);
    });

    test('observarPendientes trae las ocultas marcadas y avisa cuando cambia', () async {
      await agendar('age-1');
      await agendar('sin-espacio', espacio: 'esp-que-no-llego');
      final lecturas = <Map<String, bool>>[];
      final sub = fuente.observarPendientes(colportorId: 'col-1', desde: desde).listen((l) {
        lecturas.add({for (final a in l) a.visita.agendaId: a.oculta});
      });
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(lecturas.last, {'age-1': false, 'sin-espacio': false});

      await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 25));
      await pumpEventQueue();
      expect(lecturas.last, {'age-1': true, 'sin-espacio': false});

      await bajaDeUbicacion('ub-1');
      await pumpEventQueue();
      expect(lecturas.last, {'age-1': false, 'sin-espacio': false});
    });

    test('con el conciliador: la baja saca el aviso y la reactivación lo devuelve', () async {
      await agendar('age-1');
      final recordatorios = RecordatoriosEnMemoria();
      final conciliador = ConciliadorRecordatoriosOcultos(recordatorios);
      final sub = fuente
          .observarPendientes(colportorId: 'col-1', desde: desde)
          .listen((l) => unawaited(conciliador.aplicar(l)));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(recordatorios.llamadas, isEmpty);

      await bajaDeUbicacion('ub-1', cuando: DateTime.utc(2026, 10, 25));
      await pumpEventQueue();
      expect(recordatorios.llamadas, ['cancelar:age-1']);

      await bajaDeUbicacion('ub-1');
      await pumpEventQueue();
      expect(recordatorios.llamadas, ['cancelar:age-1', 'programar:age-1']);
      expect(recordatorios.programados.keys, ['age-1']);
    });
  });
}
