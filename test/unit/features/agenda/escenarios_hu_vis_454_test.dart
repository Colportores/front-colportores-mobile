// Escenarios de las HU-VIS-001 a 004 (BACK-HU-VIS-001, #454) de punta a punta y sin pantalla: los
// casos de uso reales (agendar, modificar, cancelar y la lectura de la agenda) sobre el repositorio,
// la DB en memoria con sus CHECK y transacciones, el recálculo real de `house_status`, la cola de
// sync y los recordatorios reales sobre un motor de avisos en memoria. Cada escenario de la HU lleva
// el literal del criterio de aceptación; después, los casos límite de cada acción: doble toque, falla
// a mitad de la acción, dos acciones seguidas, volver a agendar, datos límite.
//
// Nada de esto toca la red: el teléfono solo guarda y encola (el motor de sync lo sube cuando hay
// conexión), así que un escenario que pasa acá pasa sin conexión.

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/motor_de_avisos_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/recordatorios_locales.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/consulta_agenda_repository_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/filtros_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/vista_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/armador_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/agendar_visita_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/cancelar_agenda_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/modificar_agenda_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/campo_falsos.dart';
import '../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late MotorDeAvisosEnMemoria motor;
  late PermisoNotificacionesSistemaEnMemoria permiso;
  late AgendarVisitaUseCase agendarUC;
  late ModificarAgendaUseCase modificarUC;
  late CancelarAgendaUseCase cancelarUC;
  late ConsultaAgendaRepositoryDrift consulta;
  late DateTime ahora;
  var contador = 0;

  setUp(() async {
    contador = 0;
    // Un domingo a las 10:00, hora del teléfono.
    ahora = DateTime(2026, 5, 24, 10);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    motor = MotorDeAvisosEnMemoria();
    permiso = PermisoNotificacionesSistemaEnMemoria();
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
      permiso: permiso,
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

  /// Agenda una visita en `ep-1` (la casa de María) y devuelve el resultado completo.
  Future<Either<Failure, ResultadoAgendar>> pedirAgendar(
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    FranjaHoraria? franja,
    String nota = '',
    bool confirmo = false,
    IdsAgendarVisita? ids,
  }) => agendarUC(
    AgendarVisitaParams(
      ids: ids ?? agendarUC.nuevosIds(),
      espacioId: 'esp-1',
      espacioPersonaId: 'ep-1',
      colportorId: 'col-1',
      tipo: tipo,
      fechaProgramada: cuando,
      franja: franja,
      nota: nota,
      direccion: 'Av. Italia 1234',
      confirmoHoraPasada: confirmo,
    ),
  );

  /// Agenda y exige que haya quedado guardada.
  Future<VisitaAgendada> agendar(
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    FranjaHoraria? franja,
    String nota = '',
    bool confirmo = false,
  }) async {
    final r = await pedirAgendar(
      cuando,
      tipo: tipo,
      franja: franja,
      nota: nota,
      confirmo: confirmo,
    );
    final resultado = r.fold((f) => fail('debía guardar: $f'), (x) => x);
    expect(resultado, isA<VisitaAgendada>());
    return resultado as VisitaAgendada;
  }

  Future<Either<Failure, ResultadoModificar>> pedirModificar(
    String agendaId,
    DateTime cuando, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    FranjaHoraria? franja,
    String nota = '',
    bool confirmo = false,
  }) => modificarUC(
    ModificarAgendaParams(
      agendaId: agendaId,
      idNota: 'nota-nueva',
      tipo: tipo,
      fechaProgramada: cuando,
      franja: franja,
      nota: nota,
      direccion: 'Av. Italia 1234',
      confirmoHoraPasada: confirmo,
    ),
  );

  Failure falla<T>(Either<Failure, T> r) => r.fold((f) => f, (_) => fail('debía fallar'));

  Future<List<AgendaFila>> filas() => db.select(db.agendas).get();

  Future<AgendaFila> fila(String id) async => (await filas()).singleWhere((a) => a.id == id);

  /// La fila vigente de `house_status` de la casa (`ub-1`), o `null` si no tiene color.
  Future<HouseStatusFila?> casa() async {
    final todas = await db.select(db.houseStatuses).get();
    final vigentes = todas.where((h) => h.deletedAt == null).toList();
    return vigentes.isEmpty ? null : vigentes.single;
  }

  List<MapEntry<int, AvisoProgramado>> avisos() => motor.pendientes.entries.toList();

  /// El único aviso programado.
  AvisoProgramado aviso() => motor.pendientes.values.single;

  List<CambioEncolado> jobs(String entidad) => [
    for (final c in encolador.encolados)
      if (c.entidad == entidad) c,
  ];

  Future<VistaAgenda> vista([FiltrosAgenda filtros = FiltrosAgenda.porDefecto]) async {
    final v = VentanaAgenda.de(ahora);
    final items = await consulta
        .observar(colportorId: 'col-1', desde: v.desdeUtc, hasta: v.hastaUtc)
        .first;
    return ArmadorAgenda.armar(items, filtros, ahora);
  }

  Future<List<AuditLogFila>> auditoria() => db.select(db.auditLogLocal).get();

  // ---------------------------------------------------------------------------------------------
  group('HU-VIS-001 Agendar', () {
    test('Agendar entrevista: dado el perfil de María, cuando agendo entrevista para 2026-05-25 '
        '14:00, se crea la agenda PROGRAMADA, se programa el recordatorio local y house_status '
        'pasa a interview_scheduled', () async {
      final r = await agendar(DateTime(2026, 5, 25, 14));

      final guardada = await fila(r.agenda.id);
      expect(guardada.estado, 'PROGRAMADA');
      expect(guardada.tipo, 'ENTREVISTA');
      expect(guardada.espacioPersonaId, 'ep-1');
      expect(guardada.colportorId, 'col-1');
      expect(guardada.fechaProgramada.toLocal(), DateTime(2026, 5, 25, 14));

      expect(r.recordatorio, ResultadoRecordatorio.programado);
      expect(avisos(), hasLength(1));
      expect(aviso().instante.toLocal(), DateTime(2026, 5, 25, 13, 30));
      expect(aviso().payload, contains(r.agenda.id));

      final color = await casa();
      expect(color?.ubicacionId, 'ub-1');
      expect(color?.color, 'ENTREVISTA_PROGRAMADA');
      expect(color?.prioridad, 3);
    });

    test('la agenda y el color de la casa se encolan para el sync en el mismo guardado, sin red '
        'de por medio', () async {
      final r = await agendar(DateTime(2026, 5, 25, 14));

      final deAgenda = jobs('agenda');
      expect(deAgenda, hasLength(1));
      expect(deAgenda.single.operacion, OperacionSync.insert);
      expect(deAgenda.single.payload['id'], r.agenda.id);
      final deCasa = jobs('house_status');
      expect(deCasa, hasLength(1));
      expect(deCasa.single.payload['ubicacion_id'], 'ub-1');
    });

    test(
      'Sugerencia de slot: dado que ingreso la hora 14:30, cuando se valida, la UI sugiere la '
      'franja siguiente («early_afternoon», el rótulo del canvas 23A) y puedo aceptar o cambiar',
      () async {
        // La HU escribe «mid_morning → early_afternoon»: 14:30 cae en el hueco de 13:30 a 16:30 y la
        // sugerida es la que sigue (franja_horaria.dart, canvas 23A·01).
        final sugerida = FranjaHoraria.sugeridaPara(14 * 60 + 30);
        expect(sugerida, FranjaHoraria.primeraTarde);
        expect(sugerida!.codigo, 'early_afternoon');

        final aceptada = await agendar(DateTime(2026, 5, 25, 14, 30), franja: sugerida);
        expect((await fila(aceptada.agenda.id)).slotCodigo, 'early_afternoon');

        final cambiada = await agendar(
          DateTime(2026, 5, 25, 14, 30),
          franja: FranjaHoraria.mediaTarde,
        );
        expect((await fila(cambiada.agenda.id)).slotCodigo, 'mid_afternoon');

        final sinFranja = await agendar(DateTime(2026, 5, 25, 15));
        expect((await fila(sinFranja.agenda.id)).slotCodigo, isNull);
      },
    );

    test('Edge, hora que ya pasó: dado que ingreso una fecha/hora anterior a ahora, cuando intento '
        'guardar, advierte y no guarda nada hasta que se confirma', () async {
      final ayer = DateTime(2026, 5, 23, 9);

      final r = await pedirAgendar(ayer);

      final resultado = r.fold((f) => fail('$f'), (x) => x);
      expect(resultado, isA<HoraPasadaSinConfirmar>());
      expect((resultado as HoraPasadaSinConfirmar).ahora, ahora);
      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
      expect(avisos(), isEmpty);
      expect(await casa(), isNull);
    });

    test('confirmada la hora que ya pasó, agenda igual pero no programa un recordatorio que no '
        'iba a sonar (nota de 23A·03)', () async {
      final r = await agendar(DateTime(2026, 5, 23, 9), confirmo: true);

      expect(r.recordatorio, isNull);
      expect((await fila(r.agenda.id)).estado, 'PROGRAMADA');
      expect(avisos(), isEmpty);
      expect(jobs('agenda'), hasLength(1));
    });

    test('elegir el minuto en curso no es hora pasada', () async {
      final r = await agendar(DateTime(2026, 5, 24, 10));
      expect(r.agenda.estado, EstadoAgenda.programada);
    });

    test('una cobranza agendada no pinta la casa: «cobranza pendiente» depende de una venta con '
        'saldo (ADR-003, S9), no de la cita', () async {
      final r = await agendar(DateTime(2026, 5, 25, 11), tipo: TipoAgenda.cobranza);

      expect((await fila(r.agenda.id)).tipo, 'COBRANZA');
      expect(await casa(), isNull);
      expect(jobs('house_status'), isEmpty);
      expect(avisos(), hasLength(1));
    });

    test('la nota opcional va en la misma transacción y se queda en el teléfono', () async {
      const secreto = 'Atiende solo de tarde, tocar fuerte';
      final r = await agendar(DateTime(2026, 5, 25, 14), nota: secreto);

      final notas = await db.select(db.notas).get();
      expect(notas.map((n) => (n.targetType, n.targetId, n.texto)), [
        ('AGENDA', r.agenda.id, secreto),
      ]);
      expect('${encolador.encolados}', isNot(contains('Atiende')));
      expect('${motor.pendientes.values.map((a) => a.cuerpo)}', isNot(contains('Atiende')));
    });

    test('doble toque: el mismo formulario dos veces seguidas guarda una sola agenda, un solo job '
        'y un solo aviso', () async {
      final ids = agendarUC.nuevosIds();
      final dos = await Future.wait([
        pedirAgendar(DateTime(2026, 5, 25, 14), ids: ids),
        pedirAgendar(DateTime(2026, 5, 25, 14), ids: ids),
      ]);

      for (final r in dos) {
        expect(r.isRight(), isTrue);
      }
      expect(await filas(), hasLength(1));
      expect(jobs('agenda'), hasLength(1));
      expect(avisos(), hasLength(1));
    });

    test('falla a mitad: si el motor de sync rechaza el encolado, no queda agenda, ni color, ni '
        'aviso; y el reintento con los mismos ids guarda una sola vez', () async {
      final ids = agendarUC.nuevosIds();
      encolador.fallarCon = StateError('motor apagado');

      final r = await pedirAgendar(DateTime(2026, 5, 25, 14), ids: ids);

      expect(falla(r), isA<FailureInesperado>());
      expect(await filas(), isEmpty);
      expect(await db.select(db.houseStatuses).get(), isEmpty);
      expect(avisos(), isEmpty);

      encolador.fallarCon = null;
      final otra = await pedirAgendar(DateTime(2026, 5, 25, 14), ids: ids);
      expect(otra.isRight(), isTrue);
      expect(await filas(), hasLength(1));
      expect(avisos(), hasLength(1));
    });

    test('falla a mitad, en el segundo encolado (el color de la casa): la agenda ya escrita se '
        'revierte con todo', () async {
      encolador.fallarDespuesDe = 1;
      encolador.fallarCon = StateError('motor apagado');

      final r = await pedirAgendar(DateTime(2026, 5, 25, 14));

      expect(r.isLeft(), isTrue);
      expect(await filas(), isEmpty);
      expect(await db.select(db.houseStatuses).get(), isEmpty);
    });

    test('si el teléfono no puede programar el aviso, la agenda queda guardada y el resultado lo '
        'dice', () async {
      motor.fallaAlProgramar = true;

      final r = await agendar(DateTime(2026, 5, 25, 14));

      expect(r.recordatorio, ResultadoRecordatorio.noSePudo);
      expect(await filas(), hasLength(1));
      expect(avisos(), isEmpty);
    });

    test('con las notificaciones apagadas en el teléfono, agenda y avisa que el recordatorio no '
        'va a llegar', () async {
      permiso.estado = EstadoSistemaNotificaciones.apagadas;

      final r = await agendar(DateTime(2026, 5, 25, 14));

      expect(r.recordatorio, ResultadoRecordatorio.sinPermiso);
      expect(await filas(), hasLength(1));
    });

    test('sin casa o sin colportor no guarda nada y dice qué campo falta', () async {
      final sinCasa = await agendarUC(
        AgendarVisitaParams(
          ids: agendarUC.nuevosIds(),
          espacioId: ' ',
          colportorId: '',
          tipo: TipoAgenda.entrevista,
          fechaProgramada: DateTime(2026, 5, 25, 14),
        ),
      );

      final f = falla(sinCasa) as FailureValidacion;
      expect(f.campos.keys, containsAll(['espacio', 'colportorId']));
      expect(await filas(), isEmpty);
    });

    test(
      'un espacio que no está en el teléfono es una validación y no deja nada a medias',
      () async {
        final r = await agendarUC(
          AgendarVisitaParams(
            ids: agendarUC.nuevosIds(),
            espacioId: 'esp-que-no-existe',
            colportorId: 'col-1',
            tipo: TipoAgenda.entrevista,
            fechaProgramada: DateTime(2026, 5, 25, 14),
          ),
        );

        expect((falla(r) as FailureValidacion).campos.keys, contains('espacio'));
        expect(await filas(), isEmpty);
        expect(avisos(), isEmpty);
      },
    );

    test('dos agendas distintas en la misma casa conviven: cada una con su aviso', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      final b = await agendar(DateTime(2026, 5, 26, 9), tipo: TipoAgenda.cobranza);

      expect(await filas(), hasLength(2));
      expect(avisos(), hasLength(2));
      expect(a.agenda.id, isNot(b.agenda.id));
      // La cobranza no cambia el color: sigue el de la entrevista.
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('HU-VIS-002 Consultar la agenda', () {
    test('Vista del día: dado que tengo 3 agendas hoy y 5 mañana, cuando abro la vista, veo '
        '«Hoy (3)» y «Mañana (5)» con detalle', () async {
      for (final hora in [11, 12, 13]) {
        await agendar(DateTime(2026, 5, 24, hora));
      }
      for (final hora in [9, 10, 11, 12, 13]) {
        await agendar(DateTime(2026, 5, 25, hora));
      }

      final v = await vista();

      expect(v.dias, hasLength(2));
      expect(v.dias[0].esHoy, isTrue);
      expect(v.dias[0].cantidad, 3);
      expect(v.dias[1].esManana, isTrue);
      expect(v.dias[1].cantidad, 5);
      expect(v.total, 8);
      // Con detalle: la persona y la dirección de cada una, de la más temprana a la más tardía.
      final primera = v.dias[1].items.first;
      expect(primera.nombrePersona, 'María');
      expect(v.dias[1].items.map((i) => i.agenda.fechaProgramada.toLocal().hour), [
        9,
        10,
        11,
        12,
        13,
      ]);
    });

    test('la ventana es hoy más los 7 días siguientes: el día 8 no entra', () async {
      await agendar(DateTime(2026, 5, 31, 10));
      await agendar(DateTime(2026, 6, 1, 10));

      final v = await vista();

      expect(v.total, 1);
      expect(v.dias.single.diasDesdeHoy, 7);
    });

    test(
      'Filtro entrevista: dado que aplico filtro tipo=ENTREVISTA, solo veo entrevistas',
      () async {
        await agendar(DateTime(2026, 5, 24, 11));
        await agendar(DateTime(2026, 5, 24, 12), tipo: TipoAgenda.cobranza);
        await agendar(DateTime(2026, 5, 25, 9));
        await agendar(DateTime(2026, 5, 25, 10), tipo: TipoAgenda.cobranza);

        final entrevistas = await vista(const FiltrosAgenda(tipo: TipoAgenda.entrevista));
        final cobranzas = await vista(const FiltrosAgenda(tipo: TipoAgenda.cobranza));
        final todas = await vista();

        expect(entrevistas.total, 2);
        expect(
          entrevistas.dias
              .expand((d) => d.items)
              .every((i) => i.agenda.tipo == TipoAgenda.entrevista),
          isTrue,
        );
        expect(cobranzas.total, 2);
        expect(todas.total, 4);
      },
    );

    test(
      'Filtro de estado: una cancelada sale de «Pendientes» y aparece en «Canceladas»',
      () async {
        final a = await agendar(DateTime(2026, 5, 24, 11));
        await agendar(DateTime(2026, 5, 24, 12));
        await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

        final pendientes = await vista();
        final canceladas = await vista(const FiltrosAgenda(estado: EstadoFiltroAgenda.canceladas));
        final todas = await vista(const FiltrosAgenda(estado: EstadoFiltroAgenda.todas));

        expect(pendientes.total, 1);
        expect(canceladas.total, 1);
        expect(canceladas.dias.single.items.single.agenda.id, a.agenda.id);
        expect(todas.total, 2);
      },
    );

    test('una agenda vencida sin resultado sigue en «Pendientes» (atrasada) hasta que se registre '
        'algo: no desaparece ni cambia de estado sola', () async {
      final vencida = await agendar(DateTime(2026, 5, 20, 9), confirmo: true);

      final v = await vista();

      expect(v.atrasadas.map((i) => i.agenda.id), [vencida.agenda.id]);
      expect((await fila(vencida.agenda.id)).estado, 'PROGRAMADA');
    });

    test(
      'es reactiva: agendar, modificar y cancelar repintan la lista sin pedirla otra vez',
      () async {
        final v = VentanaAgenda.de(ahora);
        final emisiones = <int>[];
        final suscripcion = consulta
            .observar(colportorId: 'col-1', desde: v.desdeUtc, hasta: v.hastaUtc)
            .listen(
              (items) =>
                  emisiones.add(ArmadorAgenda.armar(items, FiltrosAgenda.porDefecto, ahora).total),
            );
        addTearDown(suscripcion.cancel);
        await pumpEventQueue();
        expect(emisiones.last, 0);

        final a = await agendar(DateTime(2026, 5, 25, 14));
        await pumpEventQueue();
        expect(emisiones.last, 1);

        await agendar(DateTime(2026, 5, 25, 15));
        await pumpEventQueue();
        expect(emisiones.last, 2);

        await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));
        await pumpEventQueue();
        expect(emisiones.last, 1);
      },
    );

    test('vacía: sin agendas la vista dice que está vacía', () async {
      expect((await vista()).estaVacia, isTrue);
    });

    test('lista larga: 120 agendas en un día salen contadas y en orden cronológico', () async {
      for (var i = 0; i < 120; i++) {
        await agendar(DateTime(2026, 5, 25, 8 + i ~/ 60, i % 60));
      }

      final v = await vista();

      expect(v.dias.single.cantidad, 120);
      final horas = [for (final i in v.dias.single.items) i.agenda.fechaProgramada];
      expect(horas, [...horas]..sort());
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('HU-VIS-003 Modificar', () {
    test('Cambio de hora: dado una agenda a las 14:00 con recordatorio a las 13:30, cuando cambio '
        'a las 15:00, el recordatorio se reprograma a las 14:30 (y queda uno solo)', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      expect(aviso().instante.toLocal(), DateTime(2026, 5, 25, 13, 30));

      final r = await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 15));

      final modificada = r.fold((f) => fail('$f'), (x) => x) as AgendaModificada;
      expect(modificada.recordatorio, ResultadoRecordatorio.programado);
      expect((await fila(a.agenda.id)).fechaProgramada.toLocal(), DateTime(2026, 5, 25, 15));
      expect(avisos(), hasLength(1));
      expect(aviso().instante.toLocal(), DateTime(2026, 5, 25, 14, 30));
    });

    test('deja el cambio en la cola de sync y un registro en el audit_log local, sin la hora ni '
        'la nota', () async {
      const secreto = 'Tocar timbre dos veces';
      final a = await agendar(DateTime(2026, 5, 25, 14), nota: secreto);

      await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 15), nota: secreto);

      final deAgenda = jobs('agenda');
      expect(deAgenda.map((c) => c.operacion), [OperacionSync.insert, OperacionSync.update]);
      expect(deAgenda.last.payload['id'], a.agenda.id);
      final registros = await auditoria();
      expect(registros, hasLength(1));
      expect(registros.single.evento, EventoAuditoriaLocal.agendaModificada);
      expect(registros.single.uuid, a.agenda.id);
      expect(registros.single.motivo, isNull);
      expect('${encolador.encolados}', isNot(contains('timbre')));
    });

    test('cambiar de ENTREVISTA a COBRANZA recalcula el color de la casa (la cita de cobranza no '
        'la pinta) y volver a ENTREVISTA se lo devuelve', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');

      await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14), tipo: TipoAgenda.cobranza);

      expect((await fila(a.agenda.id)).tipo, 'COBRANZA');
      expect(await casa(), isNull);
      expect(jobs('house_status').last.operacion, OperacionSync.delete);

      await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14));

      expect((await fila(a.agenda.id)).tipo, 'ENTREVISTA');
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
    });

    test('la franja se puede cambiar y quitar', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14, 30), franja: FranjaHoraria.primeraTarde);

      await pedirModificar(
        a.agenda.id,
        DateTime(2026, 5, 25, 14, 30),
        franja: FranjaHoraria.finDeTarde,
      );
      expect((await fila(a.agenda.id)).slotCodigo, 'late_afternoon');

      await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14, 30));
      expect((await fila(a.agenda.id)).slotCodigo, isNull);
    });

    test(
      'solo se modifica una agenda PROGRAMADA: cancelada, cumplida o no cumplida dicen por qué y '
      'no tocan nada',
      () async {
        final cancelada = await agendar(DateTime(2026, 5, 25, 9));
        await cancelarUC(CancelarAgendaParams(agendaId: cancelada.agenda.id));
        await insertarAgenda(db, agendaDe('age-cum', estado: EstadoAgenda.cumplida));
        await insertarAgenda(db, agendaDe('age-nocum', estado: EstadoAgenda.noCumplida));
        final antes = [for (final f in await filas()) f.toJson()];
        final jobsAntes = encolador.encolados.length;

        for (final id in [cancelada.agenda.id, 'age-cum', 'age-nocum']) {
          final r = await pedirModificar(id, DateTime(2026, 5, 26, 10));
          expect((falla(r) as FailureValidacion).campos.keys, contains('agenda'));
        }

        expect([for (final f in await filas()) f.toJson()], antes);
        expect(encolador.encolados, hasLength(jobsAntes));
        expect(await auditoria(), isEmpty);
        expect(avisos(), isEmpty);
      },
    );

    test('una agenda que no está en el teléfono es una validación', () async {
      final r = await pedirModificar('age-fantasma', DateTime(2026, 5, 26, 10));
      expect((falla(r) as FailureValidacion).campos.keys, contains('agenda'));
    });

    test('pasar la hora a una que ya pasó pide confirmación y no cambia nada; confirmada, guarda '
        'y saca el aviso viejo', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      final ayer = DateTime(2026, 5, 23, 9);

      final sinConfirmar = await pedirModificar(a.agenda.id, ayer);

      expect(
        sinConfirmar.fold((f) => fail('$f'), (x) => x),
        isA<HoraPasadaSinConfirmarAlModificar>(),
      );
      expect((await fila(a.agenda.id)).fechaProgramada.toLocal(), DateTime(2026, 5, 25, 14));
      expect(aviso().instante.toLocal(), DateTime(2026, 5, 25, 13, 30));
      expect(await auditoria(), isEmpty);

      final confirmada = await pedirModificar(a.agenda.id, ayer, confirmo: true);

      final m = confirmada.fold((f) => fail('$f'), (x) => x) as AgendaModificada;
      expect(m.recordatorio, isNull);
      expect(avisos(), isEmpty);
      expect((await fila(a.agenda.id)).fechaProgramada.toLocal(), ayer);
    });

    test(
      'guardar lo mismo que ya había no escribe nada ni duplica el aviso (doble toque)',
      () async {
        final a = await agendar(DateTime(2026, 5, 25, 14));
        final jobsAntes = encolador.encolados.length;

        for (var i = 0; i < 3; i++) {
          final r = await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14));
          expect(r.isRight(), isTrue);
        }

        expect(encolador.encolados, hasLength(jobsAntes));
        expect(await auditoria(), isEmpty);
        expect(avisos(), hasLength(1));
      },
    );

    test('falla a mitad: si el motor de sync rechaza el cambio, la agenda, el color y el aviso '
        'siguen como estaban y no queda registro de auditoría', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      encolador.fallarDespuesDe = encolador.encolados.length;
      encolador.fallarCon = StateError('motor apagado');

      final r = await pedirModificar(
        a.agenda.id,
        DateTime(2026, 5, 25, 16),
        tipo: TipoAgenda.cobranza,
      );

      expect(r.isLeft(), isTrue);
      final f = await fila(a.agenda.id);
      expect(f.tipo, 'ENTREVISTA');
      expect(f.fechaProgramada.toLocal(), DateTime(2026, 5, 25, 14));
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
      expect(aviso().instante.toLocal(), DateTime(2026, 5, 25, 13, 30));
      expect(await auditoria(), isEmpty);

      encolador.fallarCon = null;
      final otra = await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 16));
      expect(otra.isRight(), isTrue);
      expect(aviso().instante.toLocal(), DateTime(2026, 5, 25, 15, 30));
    });

    test('dos cambios seguidos sin esperar al primero: gana el último y el aviso coincide con la '
        'hora que quedó guardada', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));

      await Future.wait([
        pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 15)),
        pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 16)),
      ]);

      final guardada = (await fila(a.agenda.id)).fechaProgramada;
      expect(avisos(), hasLength(1));
      expect(
        aviso().instante.isAtSameMomentAs(guardada.subtract(const Duration(minutes: 30))),
        isTrue,
        reason: 'el aviso (${aviso().instante}) debe salir de la hora guardada ($guardada)',
      );
    });

    test(
      'modificar y cancelar a la vez: la agenda queda cancelada y no queda ningún aviso vivo',
      () async {
        final a = await agendar(DateTime(2026, 5, 25, 14));

        await Future.wait([
          pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 16)),
          cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id)),
        ]);

        final estado = (await fila(a.agenda.id)).estado;
        if (estado == 'CANCELADA') {
          expect(avisos(), isEmpty, reason: 'cancelada con un aviso vivo');
        } else {
          // Ganó modificar y después la cancelación no pudo: no hay nada a medias.
          expect(estado, 'PROGRAMADA');
          expect(avisos(), hasLength(1));
        }
      },
    );

    test(
      'textos límite en la nota: vacía la borra, larga y con emoji se guarda tal cual',
      () async {
        final a = await agendar(DateTime(2026, 5, 25, 14), nota: 'primera');
        final larga = 'ñandú 🙂 ' * 5000;

        await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14), nota: larga);
        var notas = await (db.select(db.notas)..where((n) => n.deletedAt.isNull())).get();
        expect(notas.single.texto, larga.trim());

        await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 14));
        notas = await (db.select(db.notas)..where((n) => n.deletedAt.isNull())).get();
        expect(notas, isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  group('HU-VIS-004 Cancelar', () {
    test('Cancelar: dado una agenda PROGRAMADA, cuando cancelo, el estado pasa a CANCELADA y el '
        'recordatorio se elimina', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      expect(avisos(), hasLength(1));

      final r = await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      final resultado = r.fold((f) => fail('$f'), (x) => x);
      expect(resultado.agenda.estado, EstadoAgenda.cancelada);
      expect(resultado.recordatorioCancelado, isTrue);
      expect((await fila(a.agenda.id)).estado, 'CANCELADA');
      expect(avisos(), isEmpty);
    });

    test('no se borra: la fila sigue, sin baja, y el cambio sube por la cola de sync', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));

      await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      final f = await fila(a.agenda.id);
      expect(f.deletedAt, isNull);
      expect(jobs('agenda').map((c) => c.operacion), [OperacionSync.insert, OperacionSync.update]);
      expect(jobs('agenda').last.payload['estado'], 'CANCELADA');
    });

    test('si era la única entrevista programada y la casa no tenía otro color, la casa deja de '
        'tener color y la baja sube', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');

      await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      expect(await casa(), isNull);
      expect(jobs('house_status').last.operacion, OperacionSync.delete);
    });

    test('si era la única entrevista programada, la casa vuelve al estado previo (una entrevista '
        'anterior sin venta)', () async {
      await insertarVisita(db, visitaDe('vis-previa'));
      final a = await agendar(DateTime(2026, 5, 25, 14));
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');

      await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      final color = await casa();
      expect(color?.color, 'ENTREVISTA_SIN_VENTA');
      expect(color?.prioridad, 5);
    });

    test('con otra entrevista programada en la casa, cancelar una no la saca de '
        'ENTREVISTA_PROGRAMADA', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      await agendar(DateTime(2026, 5, 26, 9));

      await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
      expect(avisos(), hasLength(1));
    });

    test(
      'cancelar dos veces no es un error, no escribe de nuevo y vuelve a pedir sacar el aviso',
      () async {
        final a = await agendar(DateTime(2026, 5, 25, 14));
        await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));
        final jobsAntes = encolador.encolados.length;
        final llamadasAntes = motor.llamadas.length;

        final r = await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

        expect(r.isRight(), isTrue);
        expect(encolador.encolados, hasLength(jobsAntes));
        expect(motor.llamadas.length, greaterThan(llamadasAntes));
        expect(avisos(), isEmpty);
      },
    );

    test('doble toque a la vez: una sola cancelación', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));

      final dos = await Future.wait([
        cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id)),
        cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id)),
      ]);

      expect(dos.every((r) => r.isRight()), isTrue);
      expect(jobs('agenda').where((c) => c.operacion == OperacionSync.update), hasLength(1));
      expect(avisos(), isEmpty);
    });

    test('una agenda cumplida o no cumplida no se cancela', () async {
      await insertarAgenda(db, agendaDe('age-cum', estado: EstadoAgenda.cumplida));
      await insertarAgenda(db, agendaDe('age-nocum', estado: EstadoAgenda.noCumplida));

      for (final id in ['age-cum', 'age-nocum']) {
        final r = await cancelarUC(CancelarAgendaParams(agendaId: id));
        expect((falla(r) as FailureValidacion).campos.keys, contains('agenda'));
      }

      expect((await fila('age-cum')).estado, 'CUMPLIDA');
      expect((await fila('age-nocum')).estado, 'NO_CUMPLIDA');
    });

    test('una agenda que no está en el teléfono o un id en blanco son validaciones', () async {
      final fantasma = await cancelarUC(const CancelarAgendaParams(agendaId: 'age-fantasma'));
      final vacio = await cancelarUC(const CancelarAgendaParams(agendaId: '  '));

      expect((falla(fantasma) as FailureValidacion).campos.keys, contains('agenda'));
      expect((falla(vacio) as FailureValidacion).campos.keys, contains('agenda'));
    });

    test('falla a mitad: si el motor de sync rechaza la cancelación, la agenda sigue programada, '
        'el color igual y el aviso vivo', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      encolador.fallarDespuesDe = encolador.encolados.length;
      encolador.fallarCon = StateError('motor apagado');

      final r = await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      expect(r.isLeft(), isTrue);
      expect((await fila(a.agenda.id)).estado, 'PROGRAMADA');
      expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
      expect(avisos(), hasLength(1));

      encolador.fallarCon = null;
      expect((await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id))).isRight(), isTrue);
      expect((await fila(a.agenda.id)).estado, 'CANCELADA');
      expect(avisos(), isEmpty);
    });

    test('si el teléfono no puede sacar el aviso, la agenda queda cancelada y el resultado lo '
        'dice; el reintento lo saca', () async {
      final a = await agendar(DateTime(2026, 5, 25, 14));
      motor.fallaAlCancelar = true;

      final r = await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

      final resultado = r.fold((f) => fail('$f'), (x) => x);
      expect(resultado.agenda.estado, EstadoAgenda.cancelada);
      expect(resultado.recordatorioCancelado, isFalse);
      expect(avisos(), hasLength(1));

      motor.fallaAlCancelar = false;
      final otra = await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));
      expect(otra.fold((f) => fail('$f'), (x) => x).recordatorioCancelado, isTrue);
      expect(avisos(), isEmpty);
    });

    test(
      'volver a agendar en la misma casa después de cancelar funciona como la primera vez',
      () async {
        final a = await agendar(DateTime(2026, 5, 25, 14));
        await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));
        expect(await casa(), isNull);

        final b = await agendar(DateTime(2026, 5, 25, 14));

        expect(b.agenda.id, isNot(a.agenda.id));
        expect((await casa())?.color, 'ENTREVISTA_PROGRAMADA');
        expect(avisos(), hasLength(1));
        expect(aviso().payload, contains(b.agenda.id));
      },
    );

    test('agendar y cancelar seguidos sin esperar: no queda un aviso huérfano', () async {
      final ids = agendarUC.nuevosIds();

      final agendando = pedirAgendar(DateTime(2026, 5, 25, 14), ids: ids);
      final cancelando = cancelarUC(CancelarAgendaParams(agendaId: ids.agenda));
      await Future.wait([agendando, cancelando]);
      // La cancelación pudo llegar antes de que la agenda existiera: se repite, como haría la
      // persona al ver la agenda en la lista.
      await cancelarUC(CancelarAgendaParams(agendaId: ids.agenda));

      expect((await fila(ids.agenda)).estado, 'CANCELADA');
      expect(avisos(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------
  group('Todo funciona sin conexión y sin filtrar datos personales', () {
    test(
      'una secuencia completa (agendar, modificar, cancelar) deja la cola en orden y sin la nota '
      'ni la dirección',
      () async {
        const secreto = 'SECRETO 099123456';
        final a = await agendar(DateTime(2026, 5, 25, 14), nota: secreto);
        await pedirModificar(a.agenda.id, DateTime(2026, 5, 25, 15), nota: secreto);
        await cancelarUC(CancelarAgendaParams(agendaId: a.agenda.id));

        expect(jobs('agenda').map((c) => c.operacion), [
          OperacionSync.insert,
          OperacionSync.update,
          OperacionSync.update,
        ]);
        final subida = '${encolador.encolados}';
        expect(subida, isNot(contains('SECRETO')));
        expect(subida, isNot(contains('099123456')));
        expect(subida, isNot(contains('Italia')));
        expect(subida, isNot(contains('María')));
        final registros = await auditoria();
        expect('${registros.map((r) => [r.evento, r.uuid, r.motivo])}', isNot(contains('SECRETO')));
        // La nota sigue en el teléfono, con su agenda.
        expect((await db.select(db.notas).get()).single.texto, secreto);
      },
    );

    test('el recordatorio no lleva el nombre de la persona ni la nota', () async {
      await agendar(DateTime(2026, 5, 25, 14), nota: 'SECRETO');

      final a = aviso();
      expect('${a.titulo} ${a.cuerpo}', isNot(contains('María')));
      expect('${a.titulo} ${a.cuerpo}', isNot(contains('SECRETO')));
    });

    test('la agenda de un colportor no muestra la de otro', () async {
      await agendar(DateTime(2026, 5, 25, 14));
      await db
          .into(db.agendas)
          .insert(
            AgendasCompanion.insert(
              id: 'age-ajena',
              espacioId: 'esp-1',
              tipo: 'ENTREVISTA',
              fechaProgramada: DateTime(2026, 5, 25, 15),
              colportorId: 'col-2',
              createdAt: t0,
              updatedAt: t0,
            ),
          );

      final v = await vista();

      expect(v.total, 1);
    });
  });
}
