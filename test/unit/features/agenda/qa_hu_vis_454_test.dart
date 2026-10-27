// QA de #454 (BACK-HU-VIS-001, PR #527): lo que `escenarios_hu_vis_454_test.dart` no mira. Mismo
// montaje (casos de uso reales, Drift en memoria, motor de avisos y cola de sync en memoria). Cubre
// los bordes de la ventana de la agenda, el recordatorio que ya no llega a sonar, las notas que no
// se pierden cuando algo falla, las casas dadas de baja y la privacidad de los `toString`.
//
// Para ver los bordes de día con un teléfono en Montevideo: `-e TZ=America/Montevideo`.

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/motor_de_avisos_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/recordatorios_locales.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/consulta_agenda_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/filtros_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/vista_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/armador_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/agendar_visita_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/cancelar_agenda_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/modificar_agenda_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late MotorDeAvisosEnMemoria motor;
  late AgendarVisitaUseCase agendarUC;
  late ModificarAgendaUseCase modificarUC;
  late CancelarAgendaUseCase cancelarUC;
  late ConsultaAgendaRepositoryDrift consulta;
  late DateTime ahora;
  var contador = 0;

  setUp(() async {
    contador = 0;
    ahora = DateTime(2026, 5, 24, 10);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    motor = MotorDeAvisosEnMemoria();
    final repo = AgendaRepositoryImpl(
      AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      ),
      logger: loggerMudo(),
    );
    final recordatorios = RecordatoriosLocales(
      motor: motor,
      permiso: PermisoNotificacionesSistemaEnMemoria(),
      ahora: () => ahora,
      logger: loggerMudo(),
    );
    String id() => 'id-${(++contador).toString().padLeft(4, '0')}';
    agendarUC = AgendarVisitaUseCase(repo, recordatorios, generarId: id, ahora: () => ahora);
    modificarUC = ModificarAgendaUseCase(repo, recordatorios, ahora: () => ahora);
    cancelarUC = CancelarAgendaUseCase(repo, recordatorios, ahora: () => ahora);
    consulta = ConsultaAgendaRepositoryDrift(db);
    await sembrarCasa(db);
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(id: 'per-1', nombre: 'María', createdAt: t0, updatedAt: t0),
        );
  });
  tearDown(() => db.close());

  // ---------------------------------------------------------------------------------------------
  // Ayudas.

  AgendarVisitaParams params(
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    String nota = '',
    String espacio = 'esp-1',
    String? persona = 'ep-1',
    bool confirmo = false,
    IdsAgendarVisita? ids,
  }) => AgendarVisitaParams(
    ids: ids ?? agendarUC.nuevosIds(),
    espacioId: espacio,
    espacioPersonaId: persona,
    colportorId: 'col-1',
    tipo: tipo,
    fechaProgramada: cuando,
    nota: nota,
    direccion: 'Av. Italia 1234',
    confirmoHoraPasada: confirmo,
  );

  Future<Either<Failure, ResultadoAgendar>> pedirAgendar(
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    String nota = '',
    String espacio = 'esp-1',
    String? persona = 'ep-1',
    bool confirmo = false,
    IdsAgendarVisita? ids,
  }) => agendarUC(
    params(
      cuando,
      tipo: tipo,
      nota: nota,
      espacio: espacio,
      persona: persona,
      confirmo: confirmo,
      ids: ids,
    ),
  );

  Future<VisitaAgendada> agendar(
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    String nota = '',
    bool confirmo = false,
  }) async {
    final r = await pedirAgendar(cuando, tipo: tipo, nota: nota, confirmo: confirmo);
    return r.fold((f) => fail('debía guardar: $f'), (x) => x) as VisitaAgendada;
  }

  ModificarAgendaParams paramsModificar(
    String agendaId,
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    String nota = '',
    bool confirmo = false,
  }) => ModificarAgendaParams(
    agendaId: agendaId,
    idNota: 'nota-nueva',
    tipo: tipo,
    fechaProgramada: cuando,
    nota: nota,
    direccion: 'Av. Italia 1234',
    confirmoHoraPasada: confirmo,
  );

  Future<Either<Failure, ResultadoModificar>> pedirModificar(
    String agendaId,
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    String nota = '',
    bool confirmo = false,
  }) => modificarUC(paramsModificar(agendaId, cuando, tipo: tipo, nota: nota, confirmo: confirmo));

  Failure falla<T>(Either<Failure, T> r) => r.fold((f) => f, (_) => fail('debía fallar'));

  Future<AgendaFila> fila(String id) async =>
      (await db.select(db.agendas).get()).singleWhere((a) => a.id == id);

  Future<List<NotaFila>> notasVivas() =>
      (db.select(db.notas)..where((n) => n.deletedAt.isNull())).get();

  Future<HouseStatusFila?> casa() async {
    final vigentes = (await db.select(db.houseStatuses).get()).where((h) => h.deletedAt == null);
    return vigentes.isEmpty ? null : vigentes.single;
  }

  List<AvisoProgramado> avisos() => motor.pendientes.values.toList();

  Future<VistaAgenda> vista([FiltrosAgenda filtros = FiltrosAgenda.porDefecto]) async {
    final v = VentanaAgenda.de(ahora);
    final items = await consulta
        .observar(colportorId: 'col-1', desde: v.desdeUtc, hasta: v.hastaUtc)
        .first;
    return ArmadorAgenda.armar(items, filtros, ahora);
  }

  // ---------------------------------------------------------------------------------------------
  group('Bordes de la ventana de la agenda (HU-VIS-002)', () {
    test('23:59 de hoy es «Hoy» y 00:00 es «Mañana»', () async {
      await agendar(DateTime(2026, 5, 24, 23, 59));
      await agendar(DateTime(2026, 5, 25));

      final v = await vista();

      expect(v.dias, hasLength(2));
      expect(v.dias[0].esHoy, isTrue);
      expect(v.dias[0].cantidad, 1);
      expect(v.dias[1].esManana, isTrue);
      expect(v.dias[1].cantidad, 1);
    });

    test(
      'una cita de la noche (22:30) sigue en su día aunque en UTC ya sea el siguiente',
      () async {
        await agendar(DateTime(2026, 5, 25, 22, 30));
        await agendar(DateTime(2026, 5, 24, 23, 30));

        final v = await vista();

        expect(v.dias[0].esHoy, isTrue);
        expect(v.dias[0].items.single.agenda.fechaProgramada.toLocal().hour, 23);
        expect(v.dias[1].esManana, isTrue);
        expect(v.dias[1].items.single.agenda.fechaProgramada.toLocal().hour, 22);
      },
    );

    test('el último minuto del día 7 entra y la medianoche del día 8 no', () async {
      await agendar(DateTime(2026, 5, 31, 23, 59));
      await agendar(DateTime(2026, 6, 1));

      final v = await vista();

      expect(v.total, 1);
      expect(v.dias.single.diasDesdeHoy, 7);
    });

    test('la cancelada no cuenta en el «Mañana (n)» de la vista por defecto', () async {
      await agendar(DateTime(2026, 5, 25, 9));
      final b = await agendar(DateTime(2026, 5, 25, 10));
      await cancelarUC(CancelarAgendaParams(agendaId: b.agenda.id));

      final v = await vista();

      expect(v.dias.single.cantidad, 1);
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Recordatorio que ya no llega a sonar (HU-VIS-001/003)', () {
    test('una visita en menos de la anticipación (10:20, aviso 09:50) se guarda y dice yaPaso, '
        'sin aviso', () async {
      final r = await agendar(DateTime(2026, 5, 24, 10, 20));

      expect(r.recordatorio, ResultadoRecordatorio.yaPaso);
      expect((await fila(r.agenda.id)).estado, 'PROGRAMADA');
      expect(avisos(), isEmpty);
    });

    test('justo a la anticipación (10:30, aviso 10:00 = ahora) tampoco suena', () async {
      final r = await agendar(DateTime(2026, 5, 24, 10, 30));

      expect(r.recordatorio, ResultadoRecordatorio.yaPaso);
      expect(avisos(), isEmpty);
    });

    test('pasar una agenda con aviso a dentro de 20 minutos saca el aviso viejo; volver a la '
        'tarde lo programa de nuevo (uno solo)', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      expect(avisos(), hasLength(1));

      final cerca = await pedirModificar(a.agenda.id, DateTime(2026, 5, 24, 10, 20));
      final m = cerca.fold((f) => fail('$f'), (x) => x) as AgendaModificada;
      expect(m.recordatorio, ResultadoRecordatorio.yaPaso);
      expect(avisos(), isEmpty);

      final lejos = await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14));
      final n = lejos.fold((f) => fail('$f'), (x) => x) as AgendaModificada;
      expect(n.recordatorio, ResultadoRecordatorio.programado);
      expect(avisos(), hasLength(1));
      expect(avisos().single.instante.toLocal(), DateTime(2026, 5, 25, 13, 30));
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('La nota no se pierde ni queda a medias', () {
    test('una nota de solo espacios no crea fila de nota; con espacios alrededor se guarda '
        'recortada', () async {
      await agendar(DateTime(2026, 5, 25, 14), nota: '   \n\t ');
      expect(await notasVivas(), isEmpty);

      final b = await agendar(DateTime(2026, 5, 25, 15), nota: '  tocar timbre  ');
      final notas = await notasVivas();
      expect(notas.single.texto, 'tocar timbre');
      expect(notas.single.targetId, b.agenda.id);
    });

    test('si agendar falla a mitad con una nota, no queda ninguna nota huérfana', () async {
      encolador.fallarDespuesDe = 1;
      encolador.fallarCon = StateError('motor apagado');

      final r = await pedirAgendar(DateTime(2026, 5, 25, 14), nota: 'Atiende de tarde');

      expect(r.isLeft(), isTrue);
      expect(await notasVivas(), isEmpty);
      expect(await db.select(db.notas).get(), isEmpty);
    });

    test('si modificar falla a mitad con una nota nueva, queda la nota anterior', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14), nota: 'la de antes');
      encolador.fallarDespuesDe = encolador.encolados.length;
      encolador.fallarCon = StateError('motor apagado');

      final r = await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 15), nota: 'la nueva');

      expect(r.isLeft(), isTrue);
      expect((await notasVivas()).single.texto, 'la de antes');
    });

    test('modificar solo la nota guarda la nota nueva y no duplica el aviso', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14), nota: 'vieja');

      final r = await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14), nota: 'nueva');

      expect(r.isRight(), isTrue);
      expect((await notasVivas()).single.texto, 'nueva');
      expect(avisos(), hasLength(1));
    });

    test('cancelar una agenda no borra su nota (del teléfono no se borra nada)', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14), nota: 'dejar folleto');

      await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      expect((await notasVivas()).single.texto, 'dejar folleto');
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Casas y personas dadas de baja', () {
    test('agendar en un espacio dado de baja es una validación y no deja nada', () async {
      await (db.update(
        db.espacios,
      )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0)));

      final r = await pedirAgendar(DateTime(2026, 5, 25, 14), nota: 'x');

      expect((falla(r) as FailureValidacion).campos.keys, contains('espacio'));
      expect(await db.select(db.agendas).get(), isEmpty);
      expect(await db.select(db.notas).get(), isEmpty);
      expect(avisos(), isEmpty);
    });

    test('una persona que no es de esa casa no se cuela en la agenda', () async {
      await sembrarEspacio(db, id: 'esp-9', numeroDepto: '9Z');
      await sembrarVinculo(db, id: 'ep-9', espacioId: 'esp-9', personaId: 'per-1');

      final r = await pedirAgendar(DateTime(2026, 5, 25, 14), persona: 'ep-9');

      expect((falla(r) as FailureValidacion).campos.keys, contains('persona'));
      expect(await db.select(db.agendas).get(), isEmpty);
    });

    test('sin persona (la casa entera) se agenda igual, con aviso y color', () async {
      final r = await agendar0(pedirAgendar(DateTime(2026, 5, 25, 14), persona: null));

      expect(r.recordatorio, ResultadoRecordatorio.programado);
      expect((await fila(r.agenda.id)).espacioPersonaId, isNull);
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Modificar y cancelar con varias agendas en la casa', () {
    test(
      'pasar una entrevista a COBRANZA con otra entrevista programada no apaga el color',
      () async {
        final a = await agendar(DateTime(2026, 5, 25, 14));
        await agendar(DateTime(2026, 5, 26, 9));

        await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14), tipo: TipoAgenda.cobranza);

        expect((await fila(a.agenda.id)).tipo, 'COBRANZA');
        expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
      },
    );

    test('una agenda vencida a la que solo se le corrige la nota o el tipo no vuelve a preguntar '
        'por la hora; si además mueve la hora a otra pasada, sí', () async {
      final v = await agendar(DateTime(2026, 5, 20, 9), confirmo: true);

      final soloNota = await pedirModificar(v.agenda.id, DateTime(2026, 5, 20, 9), nota: 'ya fui');
      expect(soloNota.fold((f) => fail('$f'), (x) => x), isA<AgendaModificada>());

      final otraPasada = await pedirModificar(v.agenda.id, DateTime(2026, 5, 21, 9));
      expect(
        otraPasada.fold((f) => fail('$f'), (x) => x),
        isA<HoraPasadaSinConfirmarAlModificar>(),
      );
      expect((await fila(v.agenda.id)).fechaProgramada.toLocal(), DateTime(2026, 5, 20, 9));
    });

    test('cancelar y volver a modificar la cancelada no la revive', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      final r = await pedirModificar(a.agenda.id, DateTime(2026, 5, 26, 9));

      expect((falla(r) as FailureValidacion).campos.keys, contains('agenda'));
      expect((await fila(a.agenda.id)).estado, EstadoAgenda.cancelada.codigo);
      expect(avisos(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Privacidad de los textos de depuración', () {
    test('toString de los parámetros no lleva la nota ni la dirección', () {
      const secreto = 'SECRETO-099123456';
      final agendar = params(DateTime(2026, 5, 25, 14), nota: secreto);
      final modificar = paramsModificar('age-1', DateTime(2026, 5, 25, 14), nota: secreto);

      for (final texto in ['$agendar', '$modificar']) {
        expect(texto, isNot(contains('SECRETO')));
        expect(texto, isNot(contains('Italia')));
      }
    });

    test(
      'toString del resultado y de las fallas no lleva la nota, la dirección ni la persona',
      () async {
        final r = await agendar(DateTime(2026, 5, 25, 14), nota: 'SECRETO-nota');
        final rechazada = falla(await pedirAgendar(DateTime(2026, 5, 25, 14), espacio: 'nada'));

        for (final texto in ['$r', '${r.agenda}', '$rechazada']) {
          expect(texto, isNot(contains('SECRETO')));
          expect(texto, isNot(contains('Italia')));
          expect(texto, isNot(contains('María')));
        }
      },
    );
  });
}

Future<VisitaAgendada> agendar0(Future<Either<Failure, ResultadoAgendar>> pedido) async {
  final r = await pedido;
  return r.fold((f) => fail('debía guardar: $f'), (x) => x) as VisitaAgendada;
}
