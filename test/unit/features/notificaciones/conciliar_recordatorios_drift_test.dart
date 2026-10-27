// HU-NOT-005 / issue #416 — «cada recordatorio local se guarda al dispararse» contra las tablas
// reales (AppDatabase en memoria): qué agendas tienen su aviso vencido y el recorrido completo de
// punta a punta (agenda → revisión → historial): suena con la app cerrada, se cancela antes de
// sonar, se reprograma, la revisión corre dos veces, «Borrar todas» no se deshace.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/fecha_utc_converter.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/agendas_para_recordar_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/datasources/historial_notificaciones_local_data_source_drift.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/historial_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/cambiar_preferencias_recordatorios_use_case.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/conciliar_recordatorios_use_case.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late AgendasParaRecordarDrift agendas;
  late HistorialNotificacionesRepositoryImpl historial;
  late MarcaConciliacionRecordatoriosEnMemoria marca;
  late PreferenciasRecordatoriosRepositoryEnMemoria preferencias;
  late DateTime ahora;
  late ConciliarRecordatoriosUseCase conciliar;

  // La visita es a las 15:00; con 30 minutos el aviso suena a las 14:30.
  final visita = DateTime.utc(2026, 10, 27, 15);
  final aviso = DateTime.utc(2026, 10, 27, 14, 30);
  final creada = DateTime.utc(2026, 10, 26, 9);

  Agenda agenda(
    String id, {
    DateTime? cuando,
    TipoAgenda tipo = TipoAgenda.entrevista,
    EstadoAgenda estado = EstadoAgenda.programada,
    String colportor = 'col-1',
    DateTime? guardada,
    String? ubicacionAlt,
    DateTime? borrada,
  }) => Agenda(
    id: id,
    espacioId: 'esp-1',
    espacioPersonaId: 'ep-1',
    tipo: tipo,
    fechaProgramada: cuando ?? visita,
    ubicacionAltId: ubicacionAlt,
    estado: estado,
    colportorId: colportor,
    auditoria: auditoriaDe(creada: guardada ?? creada, borrada: borrada),
  );

  Future<List<String>> ids({
    DateTime? desde,
    DateTime? hasta,
    int minutos = 30,
    String colportor = 'col-1',
  }) async => [
    for (final r in await agendas.conAvisoEntre(
      colportorId: colportor,
      desde: desde ?? DateTime.utc(2026, 10, 27, 12),
      hasta: hasta ?? DateTime.utc(2026, 10, 27, 15, 10),
      anticipacionMinutos: minutos,
    ))
      r.agendaId,
  ];

  Future<List<String>> idsDelHistorial() async {
    final filas = await db.select(db.notificacionesHistorial).get();
    return [for (final f in filas) f.id];
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    agendas = AgendasParaRecordarDrift(db);
    historial = HistorialNotificacionesRepositoryImpl(
      HistorialNotificacionesLocalDataSourceDrift(db),
      logger: loggerMudo(),
    );
    marca = MarcaConciliacionRecordatoriosEnMemoria(DateTime.utc(2026, 10, 27, 12));
    preferencias = PreferenciasRecordatoriosRepositoryEnMemoria();
    ahora = DateTime.utc(2026, 10, 27, 15, 10);
    conciliar = ConciliarRecordatoriosUseCase(
      agendas,
      preferencias,
      marca,
      RegistrarNotificacionUseCase(historial, ahora: () => ahora),
      ahora: () => ahora,
      logger: loggerMudo(),
    );
    await sembrarCasa(db);
    await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-1'))).write(
      const UbicacionesCompanion(calle: Value('Av. Italia'), numero: Value('1234')),
    );
  });
  tearDown(() => db.close());

  group('conAvisoEntre', () {
    test('dado una agenda programada cuyo aviso cayó en la ventana, la devuelve con su tipo, su '
        'hora y la dirección', () async {
      await insertarAgenda(db, agenda('age-1', tipo: TipoAgenda.cobranza));

      final r = await agendas.conAvisoEntre(
        colportorId: 'col-1',
        desde: DateTime.utc(2026, 10, 27, 12),
        hasta: DateTime.utc(2026, 10, 27, 15, 10),
        anticipacionMinutos: 30,
      );

      expect(r.single.agendaId, 'age-1');
      expect(r.single.tipo, TipoAgenda.cobranza);
      expect(r.single.fechaProgramada, visita);
      expect(r.single.direccion, 'Av. Italia 1234');
    });

    test('dado el límite de la ventana, deja afuera el aviso justo en «desde» y deja pasar el '
        'justo en «hasta»', () async {
      await insertarAgenda(db, agenda('en-desde', cuando: DateTime.utc(2026, 10, 27, 12, 30)));
      await insertarAgenda(db, agenda('en-hasta', cuando: DateTime.utc(2026, 10, 27, 15, 40)));
      await insertarAgenda(db, agenda('despues', cuando: DateTime.utc(2026, 10, 27, 15, 41)));

      expect(await ids(), ['en-hasta']);
    });

    test('dado agendas cumplidas o no cumplidas antes del aviso, canceladas, con baja o de otro '
        'colportor, no las devuelve', () async {
      await insertarAgenda(db, agenda('programada'));
      await insertarAgenda(db, agenda('cumplida', estado: EstadoAgenda.cumplida));
      await insertarAgenda(db, agenda('no-cumplida', estado: EstadoAgenda.noCumplida));
      await insertarAgenda(db, agenda('cancelada', estado: EstadoAgenda.cancelada));
      await insertarAgenda(db, agenda('con-baja', borrada: t0));
      await insertarAgenda(db, agenda('ajena', colportor: 'col-2'));

      expect(await ids(), ['programada']);
    });

    test('dado una agenda guardada después de la hora de su aviso (falta menos que la '
        'anticipación), no la devuelve: nunca tuvo recordatorio', () async {
      await insertarAgenda(db, agenda('tarde', guardada: DateTime.utc(2026, 10, 27, 14, 40)));
      await insertarAgenda(db, agenda('justo', guardada: DateTime.utc(2026, 10, 27, 14, 29)));

      expect(await ids(), ['justo']);
    });

    test('dado una agenda cumplida o no cumplida con el resultado guardado después del aviso, la '
        'devuelve; con el resultado anterior al aviso o cancelada, no', () async {
      // Agenda creada el 26/10; el aviso es a las 14:30 del 27/10.
      Future<void> resuelta(
        String id,
        EstadoAgenda estado,
        DateTime cambio, {
        String? visita,
      }) async {
        await insertarAgenda(db, agenda(id, estado: estado, guardada: creada));
        await (db.update(db.agendas)..where((a) => a.id.equals(id))).write(
          AgendasCompanion(updatedAt: Value(cambio), visitaId: Value(visita)),
        );
      }

      await resuelta('cumplida-despues', EstadoAgenda.cumplida, DateTime.utc(2026, 10, 27, 15, 20));
      await resuelta(
        'no-cumplida-despues',
        EstadoAgenda.noCumplida,
        DateTime.utc(2026, 10, 27, 16),
      );
      await resuelta('cumplida-antes', EstadoAgenda.cumplida, DateTime.utc(2026, 10, 27, 13));
      await resuelta(
        'cancelada-despues',
        EstadoAgenda.cancelada,
        DateTime.utc(2026, 10, 27, 15, 20),
      );
      // Con visita: manda el instante de la visita y no el último cambio de la agenda (que pudo ser
      // un toque de sync posterior).
      await insertarVisita(db, visitaDe('vis-1', creada: DateTime.utc(2026, 10, 27, 13)));
      await resuelta(
        'visita-antes',
        EstadoAgenda.cumplida,
        DateTime.utc(2026, 10, 27, 16),
        visita: 'vis-1',
      );

      expect(await ids(), unorderedEquals(['cumplida-despues', 'no-cumplida-despues']));
    });

    test('dado una agenda cumplida que no existía a la hora del aviso, no la devuelve', () async {
      await insertarAgenda(
        db,
        agenda(
          'tarde',
          estado: EstadoAgenda.cumplida,
          guardada: DateTime.utc(2026, 10, 27, 14, 40),
        ),
      );

      expect(await ids(), isEmpty);
    });

    test('dado otra anticipación, el aviso cae en otra hora', () async {
      await insertarAgenda(db, agenda('age-1'));

      expect(await ids(minutos: 120, desde: DateTime.utc(2026, 10, 27, 12)), ['age-1']);
      expect(await ids(minutos: 120, desde: DateTime.utc(2026, 10, 27, 13)), isEmpty);
    });

    test('dado varias, las devuelve de la más próxima a la más lejana', () async {
      await insertarAgenda(db, agenda('b', cuando: DateTime.utc(2026, 10, 27, 15)));
      await insertarAgenda(db, agenda('a', cuando: DateTime.utc(2026, 10, 27, 13)));

      expect(await ids(), ['a', 'b']);
    });

    test('dado una cobranza en otra dirección, el aviso lleva la alternativa', () async {
      await sembrarUbicacion(db, id: 'ub-2');
      await (db.update(db.ubicaciones)..where((u) => u.id.equals('ub-2'))).write(
        const UbicacionesCompanion(calle: Value('Mataojo'), numero: Value('2044')),
      );
      await insertarAgenda(db, agenda('age-1', tipo: TipoAgenda.cobranza, ubicacionAlt: 'ub-2'));

      final r = await agendas.conAvisoEntre(
        colportorId: 'col-1',
        desde: DateTime.utc(2026, 10, 27, 12),
        hasta: DateTime.utc(2026, 10, 27, 15, 10),
        anticipacionMinutos: 30,
      );

      expect(r.single.direccion, 'Mataojo 2044');
    });
  });

  group('de punta a punta (agenda → revisión → historial)', () {
    test('dado un recordatorio que sonó con la app cerrada, cuando se abre la app, queda en el '
        'historial', () async {
      await insertarAgenda(db, agenda('age-1'));

      await conciliar('col-1');

      expect(await idsDelHistorial(), ['recordatorio-age-1-${aviso.millisecondsSinceEpoch}']);
      final fila = (await db.select(db.notificacionesHistorial).get()).single;
      expect(fila.tipo, 'RECORDATORIO_VISITA');
      expect(fila.destino, 'agenda/age-1');
      expect(fila.leidaEn, isNull);
      expect(fila.recibidaEn, aviso);
      // Nada del cliente en lo que se guarda.
      expect('${fila.titulo} ${fila.detalle}', isNot(contains('Cliente')));
    });

    test('dado una visita cancelada antes de que sonara, no se guarda nada', () async {
      await insertarAgenda(db, agenda('age-1'));
      // La persona la cancela a las 13:00, antes del aviso de las 14:30.
      await (db.update(db.agendas)..where((a) => a.id.equals('age-1'))).write(
        AgendasCompanion(
          estado: Value(EstadoAgenda.cancelada.codigo),
          updatedAt: Value(DateTime.utc(2026, 10, 27, 13)),
        ),
      );

      await conciliar('col-1');

      expect(await idsDelHistorial(), isEmpty);
    });

    test('dado una visita reprogramada para más tarde, cuando se abre la app, se guarda el aviso '
        'de la hora nueva y no el de la hora vieja', () async {
      await insertarAgenda(db, agenda('age-1'));
      // A las 13:00 se pasa de las 15:00 a las 17:00: su aviso de las 14:30 ya no existe.
      await (db.update(db.agendas)..where((a) => a.id.equals('age-1'))).write(
        AgendasCompanion(
          fechaProgramada: Value(DateTime.utc(2026, 10, 27, 17)),
          updatedAt: Value(DateTime.utc(2026, 10, 27, 13)),
        ),
      );

      await conciliar('col-1');
      expect(await idsDelHistorial(), isEmpty);

      // Pasan las 16:30: suena el aviso de la hora nueva.
      ahora = DateTime.utc(2026, 10, 27, 16, 40);
      await conciliar('col-1');
      expect(await idsDelHistorial(), [
        'recordatorio-age-1-${DateTime.utc(2026, 10, 27, 16, 30).millisecondsSinceEpoch}',
      ]);
    });

    test('dado una visita que suena con la app abierta y se cumple en la misma sesión, cuando se '
        'revisa después, el aviso queda en el historial', () async {
      // La app se abrió a las 12:00 (la marca). El aviso de las 14:30 suena con la app abierta y a las
      // 15:20 se registra la visita: la agenda ya no está PROGRAMADA cuando se revisa.
      await insertarAgenda(db, agenda('age-1'));
      await (db.update(db.agendas)..where((a) => a.id.equals('age-1'))).write(
        AgendasCompanion(
          estado: Value(EstadoAgenda.cumplida.codigo),
          updatedAt: Value(DateTime.utc(2026, 10, 27, 15, 20)),
        ),
      );
      ahora = DateTime.utc(2026, 10, 27, 15, 25);

      await conciliar('col-1');

      expect(await idsDelHistorial(), ['recordatorio-age-1-${aviso.millisecondsSinceEpoch}']);
    });

    test('dado un cambio de anticipación con un aviso ya sonado, cuando se cambia, el aviso queda '
        'guardado con la anticipación de antes', () async {
      await insertarAgenda(db, agenda('age-1'));
      final cambiar = CambiarPreferenciasRecordatoriosUseCase(
        preferencias,
        ReprogramarRecordatoriosUseCase(
          agendas,
          RecordatoriosEnMemoria(),
          ahora: () => ahora,
          logger: loggerMudo(),
        ),
        antesDeCambiar: (colportorId) async {
          await conciliar(colportorId);
        },
        logger: loggerMudo(),
      );

      await cambiar(
        colportorId: 'col-1',
        previas: const PreferenciasRecordatorios(),
        nuevas: const PreferenciasRecordatorios(anticipacionMinutos: 60),
      );

      // Sonó a las 14:30 (30 minutos), no a las 14:00 (los 60 de ahora).
      expect(await idsDelHistorial(), ['recordatorio-age-1-${aviso.millisecondsSinceEpoch}']);
      expect(marca.marca, ahora);
      expect((await preferencias.leer()).anticipacionMinutos, 60);

      // Y con los 60 nuevos, la revisión siguiente no inventa el aviso de las 14:00.
      ahora = ahora.add(const Duration(minutes: 5));
      await conciliar('col-1');
      expect(await idsDelHistorial(), hasLength(1));
    });

    test('dado que la revisión corre dos veces, el aviso queda una sola vez', () async {
      await insertarAgenda(db, agenda('age-1'));

      await conciliar('col-1');
      marca.marca = DateTime.utc(2026, 10, 27, 12);
      await conciliar('col-1');
      await conciliar('col-1');

      expect(await idsDelHistorial(), hasLength(1));
    });

    test('dado que la persona borró todo el historial, cuando vuelve a abrir la app, el aviso '
        'borrado no vuelve', () async {
      await insertarAgenda(db, agenda('age-1'));
      await conciliar('col-1');
      await BorrarTodasLasNotificacionesUseCase(historial)();
      expect(await idsDelHistorial(), isEmpty);

      ahora = ahora.add(const Duration(hours: 1));
      await conciliar('col-1');

      expect(await idsDelHistorial(), isEmpty);
    });

    test('dado un aviso guardado hace más de 90 días, no se vuelve a guardar', () async {
      marca.marca = DateTime.utc(2026, 1, 1);
      await insertarAgenda(
        db,
        agenda('vieja', cuando: DateTime.utc(2026, 5, 1, 15), guardada: DateTime.utc(2026, 4, 1)),
      );

      await conciliar('col-1');

      expect(await idsDelHistorial(), isEmpty);
    });

    test('dado «Recordatorios de agenda» apagado, no guarda nada', () async {
      preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await insertarAgenda(db, agenda('age-1'));

      await conciliar('col-1');

      expect(await idsDelHistorial(), isEmpty);
    });
  });

  test('la columna updated_at se compara en milisegundos UTC, como el resto de las fechas', () {
    // Si el conversor cambiara de unidad, la ventana de arriba dejaría de ser la que se pide.
    expect(const FechaUtcConverter().toSql(aviso), aviso.millisecondsSinceEpoch);
  });
}
