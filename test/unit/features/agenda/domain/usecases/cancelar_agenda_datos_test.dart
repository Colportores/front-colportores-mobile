// Cancelar una agenda (HU-VIS-004, #150) de punta a punta contra la DB real en memoria: el caso de
// uso, el repositorio, las tablas `agenda`/`house_status`/`nota`, el servicio real del color de la casa,
// la cola de sync y el recordatorio. Los escenarios llevan el título de la HU.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/cancelar_agenda_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AgendaRepositoryImpl repositorio;
  late RecordatoriosEnMemoria recordatorios;
  late CancelarAgendaUseCase casoDeUso;
  var reloj = t0;

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
    casoDeUso = CancelarAgendaUseCase(repositorio, recordatorios, ahora: () => reloj);
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  /// Agenda y programa el aviso, como hará el alta (HU-VIS-001).
  Future<void> agendar(
    String id, {
    TipoAgenda tipo = TipoAgenda.entrevista,
    String? espacio,
  }) async {
    await repositorio.agendar(agendaDe(id, tipo: tipo, espacio: espacio ?? 'esp-1'));
    await recordatorios.programar(
      RecordatorioDeVisita(
        agendaId: id,
        tipo: tipo,
        direccion: 'Av. Italia 1234',
        fechaProgramada: DateTime.utc(2026, 10, 25, 14),
      ),
    );
    encolador.encolados.clear();
    recordatorios.llamadas.clear();
  }

  Future<List<String>> estados() async => [
    for (final a in await db.select(db.agendas).get()) '${a.id}:${a.estado}',
  ];

  /// Los colores vigentes de las casas (la casa «sin visita» es la fila dada de baja).
  Future<List<String>> colores() async => [
    for (final h in await db.select(db.houseStatuses).get())
      if (h.deletedAt == null) h.color,
  ];
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  Future<Failure?> cancelar(String id) async =>
      (await casoDeUso(CancelarAgendaParams(agendaId: id))).fold((f) => f, (_) => null);

  group('Escenario: Cancelar', () {
    test('dado que tengo una agenda PROGRAMADA, cuando cancelo, el estado pasa a CANCELADA (no se '
        'borra), el recordatorio se elimina y la cancelación sube por el sync', () async {
      await agendar('age-1');
      expect(await colores(), ['ENTREVISTA_PROGRAMADA']);
      encolador.encolados.clear();

      expect(await cancelar('age-1'), isNull);

      final filas = await db.select(db.agendas).get();
      expect(filas.map((a) => (a.id, a.estado, a.deletedAt)), [('age-1', 'CANCELADA', null)]);
      expect(filas.single.updatedAt.isAtSameMomentAs(reloj), isTrue);
      expect(recordatorios.programados, isEmpty);
      expect(recordatorios.llamadas, ['cancelar:age-1']);
      expect(cola(), contains('agenda:update'));
    });

    test('dado que era la única entrevista programada de la casa, cuando cancelo, el color de la '
        'casa se recalcula y deja de ser «entrevista programada»', () async {
      await agendar('age-1');
      expect(await colores(), ['ENTREVISTA_PROGRAMADA']);

      encolador.encolados.clear();

      await cancelar('age-1');

      expect(await colores(), isEmpty);
      expect(cola(), containsAll(['agenda:update', 'house_status:delete']));
    });

    test('dado que la casa tiene otra entrevista programada, cuando cancelo una, la casa sigue '
        'como «entrevista programada» y el aviso de la otra no se toca', () async {
      await agendar('age-1');
      await agendar('age-2');

      await cancelar('age-1');

      expect(await colores(), ['ENTREVISTA_PROGRAMADA']);
      expect(await estados(), containsAll(['age-1:CANCELADA', 'age-2:PROGRAMADA']));
      expect(recordatorios.programados.keys, ['age-2']);
    });

    test('dado que la casa ya tenía una visita con resultado, cuando cancelo la entrevista, la '
        'casa vuelve al color de ese resultado («vuelve al estado previo»)', () async {
      final registrar = RegistrarResultadoVisitaUseCase(
        repositorio,
        generarId: () => 'visita-1',
        ahora: () => t0,
      );
      await registrar(
        const RegistrarResultadoVisitaParams(
          ids: IdsResultadoVisita(visita: 'visita-1', nota: 'nota-1'),
          espacioId: 'esp-1',
          espacioPersonaId: 'ep-1',
          colportorId: 'col-1',
          resultado: TipoResultadoVisita.noContesto,
        ),
      );
      expect(await colores(), ['SIN_CONTESTAR']);
      await agendar('age-1');
      expect(await colores(), ['ENTREVISTA_PROGRAMADA']);

      await cancelar('age-1');

      expect(await colores(), ['SIN_CONTESTAR']);
    });

    test('dado que la agenda es una cobranza, cuando cancelo, se cancela y se saca su aviso sin '
        'tocar el color de la casa', () async {
      await agendar('age-1', tipo: TipoAgenda.cobranza);
      final antes = await colores();

      await cancelar('age-1');

      expect(await estados(), ['age-1:CANCELADA']);
      expect(await colores(), antes);
      expect(recordatorios.programados, isEmpty);
    });
  });

  group('Casos límite', () {
    test('dado que cancelo dos veces, cuando llega el segundo toque, no es un error y no escribe '
        'ni encola de nuevo', () async {
      await agendar('age-1');
      await cancelar('age-1');
      encolador.encolados.clear();
      final tocadoAntes = (await db.select(db.agendas).get()).single.updatedAt;
      reloj = reloj.add(const Duration(minutes: 1));

      expect(await cancelar('age-1'), isNull);

      expect(encolador.encolados, isEmpty);
      expect((await db.select(db.agendas).get()).single.updatedAt, tocadoAntes);
      expect(await estados(), ['age-1:CANCELADA']);
    });

    test('dado que la agenda ya se cumplió, cuando cancelo, falla por el campo agenda, no cambia '
        'nada y el aviso no se toca', () async {
      await insertarAgenda(db, agendaDe('age-1', estado: EstadoAgenda.cumplida));
      await recordatorios.programar(
        RecordatorioDeVisita(
          agendaId: 'age-1',
          tipo: TipoAgenda.entrevista,
          direccion: '',
          fechaProgramada: DateTime.utc(2026, 10, 25, 14),
        ),
      );
      recordatorios.llamadas.clear();

      final falla = await cancelar('age-1');

      expect(falla, isA<FailureValidacion>());
      expect((falla! as FailureValidacion).campos.keys, ['agenda']);
      expect(await estados(), ['age-1:CUMPLIDA']);
      expect(recordatorios.llamadas, isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('dado que la agenda ya no está en el teléfono, cuando cancelo, falla por el campo agenda '
        'y no escribe nada', () async {
      final falla = await cancelar('no-existe');

      expect(falla, isA<FailureValidacion>());
      expect((falla! as FailureValidacion).campos.keys, ['agenda']);
      expect(encolador.encolados, isEmpty);
    });

    test('dado que el aviso no se puede sacar, cuando cancelo, la agenda queda cancelada y el '
        'resultado lo dice', () async {
      await agendar('age-1');
      recordatorios.puedeCancelar = false;

      final r = await casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));

      expect(r.getOrElse(() => throw StateError('falló')).recordatorioCancelado, isFalse);
      expect(await estados(), ['age-1:CANCELADA']);
    });
  });
}
