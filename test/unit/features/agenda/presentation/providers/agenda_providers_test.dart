// El cableado de las agendas y la cache `house_status` (BACK-HU-VIS-001): sin DB abierta lanzan, con
// DB escriben en ella y encolan por el encolador que cablea `encoladorSyncProvider`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
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
}
