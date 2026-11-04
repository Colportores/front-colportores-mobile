// El cableado de «Agendar una visita» (HU-VIS-001, #408) contra la DB real en memoria: la agenda queda
// guardada y encolada, la casa cambia de color solo con una entrevista y el recordatorio se programa.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/agendar_visita_use_case.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late RecordatoriosEnMemoria recordatorios;
  late ProviderContainer c;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    recordatorios = RecordatoriosEnMemoria();
    await sembrarCasa(db);
    var n = 0;
    c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(db)),
        encoladorSyncProvider.overrideWithValue(encolador),
        recordatoriosProvider.overrideWithValue(recordatorios),
        generadorIdVisitaProvider.overrideWithValue(() => 'age-${++n}'),
        relojVisitaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 23, 17, 35)),
      ],
    );
    addTearDown(c.dispose);
  });
  tearDown(() => db.close());

  AgendarVisitaParams params(
    AgendarVisitaUseCase caso, {
    TipoAgenda tipo = TipoAgenda.entrevista,
  }) => AgendarVisitaParams(
    ids: caso.nuevosIds(),
    espacioId: 'esp-1',
    espacioPersonaId: 'ep-1',
    colportorId: 'col-1',
    tipo: tipo,
    fechaProgramada: DateTime.utc(2026, 10, 24, 17, 30),
    franja: FranjaHoraria.primeraTarde,
    nota: 'Tocar el timbre',
    direccion: 'Mataojo 2044',
  );

  test(
    'dada una entrevista, cuando se agenda con la DB real, entonces guarda, encola y pinta la casa',
    () async {
      final caso = c.read(agendarVisitaUseCaseProvider);

      final r = await caso(params(caso));

      final ok = r.getOrElse(() => throw StateError('falló')) as VisitaAgendada;
      expect(ok.recordatorio, ResultadoRecordatorio.programado);
      final guardada = (await db.select(db.agendas).get()).single;
      expect(guardada.id, 'age-1');
      expect(guardada.slotCodigo, 'early_afternoon');
      expect(guardada.estado, 'PROGRAMADA');
      expect((await db.select(db.houseStatuses).get()).single.color, 'ENTREVISTA_PROGRAMADA');
      expect(encolador.encolados.map((e) => e.entidad), contains('agenda'));
      expect(recordatorios.programados['age-1']?.direccion, 'Mataojo 2044');
    },
  );

  test(
    'dada una cobranza, cuando se agenda, entonces la casa no queda como entrevista agendada',
    () async {
      final caso = c.read(agendarVisitaUseCaseProvider);

      await caso(params(caso, tipo: TipoAgenda.cobranza));

      expect((await db.select(db.agendas).get()).single.tipo, 'COBRANZA');
      final colores = (await db.select(db.houseStatuses).get()).map((h) => h.color);
      expect(colores, isNot(contains('ENTREVISTA_PROGRAMADA')));
    },
  );

  test(
    'dado el mismo formulario enviado dos veces, cuando se agenda, entonces queda una sola agenda',
    () async {
      final caso = c.read(agendarVisitaUseCaseProvider);
      final p = params(caso);

      await caso(p);
      await caso(p);

      expect(await db.select(db.agendas).get(), hasLength(1));
    },
  );

  test(
    'dada una casa que no existe, cuando se agenda, entonces falla y no programa el recordatorio',
    () async {
      final caso = c.read(agendarVisitaUseCaseProvider);
      final p = AgendarVisitaParams(
        ids: caso.nuevosIds(),
        espacioId: 'esp-que-no-existe',
        colportorId: 'col-1',
        tipo: TipoAgenda.entrevista,
        fechaProgramada: DateTime.utc(2026, 10, 24, 17, 30),
      );

      final r = await caso(p);

      expect(r.isLeft(), isTrue);
      expect(await db.select(db.agendas).get(), isEmpty);
      expect(recordatorios.llamadas, isEmpty);
    },
  );
}
