// Modificar una agenda (HU-VIS-003, #409) de punta a punta contra la DB real en memoria: el caso de uso,
// el repositorio, las tablas `agenda`/`house_status`/`nota`/`audit_log`, el servicio real del color de la
// casa, la cola de sync y el recordatorio. Los escenarios llevan el título de la HU.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/modificar_agenda_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/conciliacion_recordatorios_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AgendaRepositoryImpl repositorio;
  late RecordatoriosEnMemoria recordatorios;
  late ModificarAgendaUseCase casoDeUso;
  var reloj = t0;

  // La agenda de `agendaDe` es el 25/10/2026 14:00 UTC; el reloj arranca antes.
  final catorce = DateTime.utc(2026, 10, 25, 14);
  final quince = DateTime.utc(2026, 10, 25, 15);

  setUp(() async {
    reloj = t0.add(const Duration(minutes: 5));
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    repositorio = AgendaRepositoryImpl(
      AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      ),
      logger: loggerMudo(),
    );
    recordatorios = RecordatoriosEnMemoria();
    casoDeUso = ModificarAgendaUseCase(repositorio, recordatorios, ahora: () => reloj);
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  Future<void> agendar(String id, {TipoAgenda tipo = TipoAgenda.entrevista, String? nota}) async {
    await repositorio.agendar(
      agendaDe(id, tipo: tipo, slot: FranjaHoraria.primeraTarde.codigo),
      nota: nota == null ? null : NotaDeCampo(id: 'nota-0', texto: nota, auditoria: auditoriaDe()),
    );
    encolador.encolados.clear();
  }

  ModificarAgendaParams cambio(
    String id, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    DateTime? cuando,
    FranjaHoraria? franja = FranjaHoraria.primeraTarde,
    String nota = '',
    bool confirmo = false,
    String idNota = 'nota-1',
  }) => ModificarAgendaParams(
    agendaId: id,
    idNota: idNota,
    tipo: tipo,
    fechaProgramada: cuando ?? catorce,
    franja: franja,
    nota: nota,
    direccion: 'Av. Italia 1234',
    confirmoHoraPasada: confirmo,
  );

  Future<({Failure? falla, ResultadoModificar? resultado})> modificar(
    ModificarAgendaParams p,
  ) async {
    final r = await casoDeUso(p);
    return (falla: r.fold((f) => f, (_) => null), resultado: r.fold((_) => null, (x) => x));
  }

  Future<AgendaFila> fila(String id) =>
      (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle();
  Future<List<NotaFila>> notasDe(String id) =>
      (db.select(db.notas)..where((n) => n.targetId.equals(id))).get();
  Future<List<String>> auditoria() async => [
    for (final a in await db.select(db.auditLogLocal).get()) '${a.evento}:${a.uuid}',
  ];
  Future<List<String>> colores() async => [
    for (final h in await db.select(db.houseStatuses).get())
      if (h.deletedAt == null) h.color,
  ];
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  group('Escenario: Cambio de hora', () {
    test('dado que tengo agenda a las 14:00 con recordatorio a 13:30, cuando cambio a 15:00, el '
        'recordatorio se reprograma a 14:30 (con la hora nueva de la visita)', () async {
      await agendar('age-1');
      final r = await modificar(cambio('age-1', cuando: quince, franja: null));

      expect(r.falla, isNull);
      final ok = r.resultado! as AgendaModificada;
      expect(ok.recordatorio, ResultadoRecordatorio.programado);
      expect(ok.agenda.fechaProgramada, quince);
      expect((await fila('age-1')).fechaProgramada, quince);
      expect((await fila('age-1')).slotCodigo, isNull);
      expect(recordatorios.programados['age-1']!.fechaProgramada, quince);
      expect(recordatorios.programados['age-1']!.direccion, 'Av. Italia 1234');
    });

    test(
      'la fila sube por el sync entera, deja el registro en el audit log local (solo el id) y no '
      'toca el estado',
      () async {
        await agendar('age-1');
        await modificar(cambio('age-1', cuando: quince));

        expect(cola(), contains('agenda:update'));
        expect(await auditoria(), ['agenda_modificada:age-1']);
        expect((await fila('age-1')).estado, EstadoAgenda.programada.codigo);
      },
    );
  });

  group('Escenario: Cambio de tipo de ENTREVISTA a COBRANZA', () {
    test('actualiza house_status derivado en la misma transacción', () async {
      await agendar('age-1');
      expect(await colores(), ['ENTREVISTA_PROGRAMADA']);

      final r = await modificar(cambio('age-1', tipo: TipoAgenda.cobranza));

      expect(r.falla, isNull);
      expect((await fila('age-1')).tipo, TipoAgenda.cobranza.codigo);
      expect(await colores(), isNot(['ENTREVISTA_PROGRAMADA']));
      expect(recordatorios.programados['age-1']!.tipo, TipoAgenda.cobranza);
    });
  });

  group('Solo editable si estado = PROGRAMADA', () {
    test(
      'una agenda cumplida no se modifica: falla con el campo agenda y no escribe ni reprograma',
      () async {
        await agendar('age-1');
        await repositorio.registrarVisita(
          visitaDe('vis-1', resultado: TipoResultadoVisita.entrevista),
          agendaId: 'age-1',
        );
        encolador.encolados.clear();
        recordatorios.llamadas.clear();

        final r = await modificar(cambio('age-1', cuando: quince));

        expect(r.falla, isA<FailureValidacion>());
        expect((r.falla! as FailureValidacion).campos.keys, contains('agenda'));
        expect((await fila('age-1')).fechaProgramada, catorce);
        expect(encolador.encolados, isEmpty);
        expect(recordatorios.llamadas, isEmpty);
        expect(await auditoria(), isEmpty);
      },
    );

    test('una cancelada tampoco, y una que no existe dice que ya no está', () async {
      await agendar('age-1');
      await repositorio.cancelar('age-1', ahora: reloj);
      expect((await modificar(cambio('age-1'))).falla, isA<FailureValidacion>());
      final inexistente = await modificar(cambio('no-hay'));
      expect((inexistente.falla! as FailureValidacion).campos['agenda'], contains('ya no está'));
    });

    test('sin ids no toca la base', () async {
      await agendar('age-1');
      final r = await modificar(cambio('age-1', idNota: ' '));
      expect(r.falla, isA<FailureValidacion>());
      expect(encolador.encolados, isEmpty);
    });
  });

  group('Doble toque y reintento', () {
    test(
      'guardar dos veces lo mismo escribe una sola vez (el segundo no encola ni audita)',
      () async {
        await agendar('age-1');
        await modificar(cambio('age-1', cuando: quince));
        final colaTrasElPrimero = cola().length;
        final r = await modificar(cambio('age-1', cuando: quince));

        expect(r.falla, isNull);
        expect(cola().length, colaTrasElPrimero);
        expect(await auditoria(), ['agenda_modificada:age-1']);
      },
    );

    test(
      'no cambiar nada no escribe nada, pero sí deja el recordatorio como corresponde',
      () async {
        await agendar('age-1');
        final r = await modificar(cambio('age-1'));
        expect(r.falla, isNull);
        expect(encolador.encolados, isEmpty);
        expect(await auditoria(), isEmpty);
      },
    );

    test('dos modificaciones seguidas: gana la última y ninguna se pierde ni se mezcla', () async {
      await agendar('age-1');
      final a = modificar(cambio('age-1', cuando: quince));
      final b = modificar(
        cambio('age-1', cuando: DateTime.utc(2026, 10, 25, 16), tipo: TipoAgenda.cobranza),
      );
      await Future.wait([a, b]);

      final f = await fila('age-1');
      expect(f.fechaProgramada, DateTime.utc(2026, 10, 25, 16));
      expect(f.tipo, TipoAgenda.cobranza.codigo);
      expect(recordatorios.programados['age-1']!.fechaProgramada, DateTime.utc(2026, 10, 25, 16));
    });
  });

  group('La nota de la agenda (local-only)', () {
    test('se crea con el id del formulario, se cambia y se borra al dejarla en blanco', () async {
      await agendar('age-1');
      await modificar(cambio('age-1', nota: 'Pidió volver con el esposo'));
      var notas = await notasDe('age-1');
      expect(notas.map((n) => n.id), ['nota-1']);
      expect(notas.single.texto, 'Pidió volver con el esposo');
      // Una nota sola no toca la fila de la agenda ni la cola de sync: no es del servidor.
      expect(cola(), isEmpty);

      await modificar(cambio('age-1', nota: 'Mejor a la tarde'));
      notas = await notasDe('age-1');
      expect(notas.single.texto, 'Mejor a la tarde');

      await modificar(cambio('age-1', nota: '   '));
      notas = await notasDe('age-1');
      expect(notas.single.deletedAt, isNotNull);
      expect(await auditoria(), hasLength(3));
    });

    test('un reintento con el mismo id de nota no la duplica', () async {
      await agendar('age-1');
      await modificar(cambio('age-1', nota: 'Una nota'));
      await modificar(cambio('age-1', nota: 'Una nota'));
      expect(await notasDe('age-1'), hasLength(1));
    });

    test('cambia la nota que ya tenía desde el alta', () async {
      await agendar('age-1', nota: 'Del alta');
      await modificar(cambio('age-1', nota: 'Corregida'));
      final notas = await notasDe('age-1');
      expect(notas.single.id, 'nota-0');
      expect(notas.single.texto, 'Corregida');
    });

    test('el detalle trae la nota y la visita que cerró la agenda', () async {
      await agendar('age-1', nota: 'Del alta');
      var detalle = (await repositorio.obtenerDetalle('age-1')).getOrElse(() => null);
      expect(detalle!.nota, 'Del alta');
      expect(detalle.visita, isNull);

      await repositorio.registrarVisita(
        visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto),
        agendaId: 'age-1',
      );
      detalle = (await repositorio.obtenerDetalle('age-1')).getOrElse(() => null);
      expect(detalle!.agenda.estado, EstadoAgenda.noCumplida);
      expect(detalle.visita!.tipoResultado, TipoResultadoVisita.noContesto);
      expect((await repositorio.obtenerDetalle('nadie')).getOrElse(() => null), isNull);
    });
  });

  group('Falla a mitad del guardado', () {
    test(
      'si el encolado falla no queda nada a medias: ni la fila, ni la nota, ni el audit log, y el '
      'recordatorio sigue en su hora',
      () async {
        await agendar('age-1', nota: 'Del alta');
        await recordatorios.programar(visitaParaAviso('age-1', catorce));
        recordatorios.llamadas.clear();
        encolador.fallarCon = StateError('sin motor');

        final r = await modificar(cambio('age-1', cuando: quince, nota: 'Otra'));

        expect(r.falla, isA<FailureInesperado>());
        expect((await fila('age-1')).fechaProgramada, catorce);
        expect((await notasDe('age-1')).single.texto, 'Del alta');
        expect(await auditoria(), isEmpty);
        expect(recordatorios.llamadas, isEmpty, reason: 'el aviso solo se mueve si se guardó');
        expect(recordatorios.programados['age-1']!.fechaProgramada, catorce);
      },
    );

    test('el botón vuelve a servir: tras la falla, el mismo guardado sale bien', () async {
      await agendar('age-1');
      encolador.fallarCon = StateError('sin motor');
      expect((await modificar(cambio('age-1', cuando: quince))).falla, isNotNull);
      encolador.fallarCon = null;
      expect((await modificar(cambio('age-1', cuando: quince))).falla, isNull);
      expect((await fila('age-1')).fechaProgramada, quince);
    });
  });

  group('Edge - la hora ya pasó', () {
    test('cambiar a una hora que ya pasó pide confirmación y no guarda nada', () async {
      await agendar('age-1');
      reloj = DateTime.utc(2026, 10, 25, 18);
      final r = await modificar(cambio('age-1', cuando: quince));

      expect(r.resultado, isA<HoraPasadaSinConfirmarAlModificar>());
      expect((await fila('age-1')).fechaProgramada, catorce);
      expect(encolador.encolados, isEmpty);
    });

    test(
      'confirmada, guarda y SACA el recordatorio de la hora vieja (no promete uno que no suena)',
      () async {
        await agendar('age-1');
        await recordatorios.programar(visitaParaAviso('age-1', catorce));
        reloj = DateTime.utc(2026, 10, 25, 18);

        final r = await modificar(cambio('age-1', cuando: quince, confirmo: true));

        expect((r.resultado! as AgendaModificada).recordatorio, isNull);
        expect((await fila('age-1')).fechaProgramada, quince);
        expect(recordatorios.programados, isNot(contains('age-1')));
      },
    );

    test('una agenda ya vencida que no cambia de hora no vuelve a preguntar', () async {
      await agendar('age-1');
      reloj = DateTime.utc(2026, 10, 25, 18);
      final r = await modificar(cambio('age-1', tipo: TipoAgenda.cobranza));
      expect(r.resultado, isA<AgendaModificada>());
      expect((await fila('age-1')).tipo, TipoAgenda.cobranza.codigo);
    });
  });

  group('El recordatorio', () {
    test('la visita en menos de la anticipación: yaPaso, y la agenda queda guardada', () async {
      await agendar('age-1');
      recordatorios.resultadoForzado = ResultadoRecordatorio.yaPaso;
      final r = await modificar(cambio('age-1', cuando: quince));
      expect((r.resultado! as AgendaModificada).recordatorio, ResultadoRecordatorio.yaPaso);
      expect((await fila('age-1')).fechaProgramada, quince);
    });

    test('si el puerto lanza, la agenda igual queda guardada (noSePudo)', () async {
      await agendar('age-1');
      final r = await ModificarAgendaUseCase(
        repositorio,
        _RecordatoriosQueLanzan(),
        ahora: () => reloj,
      )(cambio('age-1', cuando: quince));
      expect(r.getOrElse(() => throw StateError('x')), isA<AgendaModificada>());
      expect((await fila('age-1')).fechaProgramada, quince);
    });
  });
}

final class _RecordatoriosQueLanzan implements Recordatorios {
  @override
  Future<ResultadoRecordatorio> programar(recordatorio) => throw StateError('plugin');

  @override
  Future<bool> cancelar(String agendaId) => throw StateError('plugin');

  @override
  Future<bool> puedeAvisar() async => true;
}
