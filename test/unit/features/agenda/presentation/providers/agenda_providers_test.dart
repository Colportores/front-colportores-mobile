// El cableado de las agendas y la cache `house_status` (BACK-HU-VIS-001): sin DB abierta lanzan, con
// DB escriben en ella y encolan por el encolador que cablea `encoladorSyncProvider`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/house_status_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

/// La DB «abierta» sin cifrado ni helper: los providers solo necesitan el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
  });
  tearDown(() => db.close());

  ProviderContainer armar({bool conDb = true}) {
    final c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(conDb ? db : null)),
        encoladorSyncProvider.overrideWithValue(encolador),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('sin la DB abierta, el repositorio de agendas y el servicio de la casa lanzan', () {
    final c = armar(conDb: false);

    expect(
      () => c.read(agendaRepositoryProvider),
      throwsA(isA<ProviderException>().having((e) => e.exception, 'exception', isA<StateError>())),
    );
    expect(
      () => c.read(houseStatusUpdaterProvider),
      throwsA(isA<ProviderException>().having((e) => e.exception, 'exception', isA<StateError>())),
    );
  });

  test('con la DB abierta, agendar guarda en ella, encola y deja la casa en su color', () async {
    await sembrarCasa(db);
    final c = armar();

    final r = await c.read(agendaRepositoryProvider).agendar(agendaDe('age-1'));

    expect(r.isRight(), isTrue);
    expect((await db.select(db.agendas).get()).single.id, 'age-1');
    expect(encolador.encolados.map((e) => e.entidad), ['agenda', 'house_status']);
    expect((await db.select(db.houseStatuses).get()).single.color, 'ENTREVISTA_PROGRAMADA');
  });

  test('con la DB abierta, el caso de uso del resultado guarda la visita con el reloj y los ids '
      'del provider', () async {
    await sembrarCasa(db);
    var n = 0;
    final c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(db)),
        encoladorSyncProvider.overrideWithValue(encolador),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 23, 16)),
      ],
    );
    addTearDown(c.dispose);
    final casoDeUso = c.read(registrarResultadoVisitaUseCaseProvider);

    final r = await casoDeUso(
      RegistrarResultadoVisitaParams(
        ids: casoDeUso.nuevosIds(),
        espacioId: 'esp-1',
        espacioPersonaId: 'ep-1',
        colportorId: 'col-1',
        resultado: TipoResultadoVisita.rechazo,
      ),
    );

    expect(r.isRight(), isTrue);
    final visita = (await db.select(db.visitas).get()).single;
    expect(
      [visita.id, visita.tipoResultado, visita.fecha],
      ['id-1', 'RECHAZO', DateTime.utc(2026, 10, 23, 16)],
    );
    expect((await db.select(db.houseStatuses).get()).single.color, 'RECHAZO');
  });

  test('sin la DB abierta, el caso de uso del resultado lanza', () {
    final c = armar(conDb: false);

    expect(
      () => c.read(registrarResultadoVisitaUseCaseProvider),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.toString(),
          'mensaje',
          contains('La base de datos local no está abierta'),
        ),
      ),
    );
  });
}
