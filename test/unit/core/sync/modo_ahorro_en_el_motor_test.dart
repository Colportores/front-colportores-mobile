// El modo ahorro de datos (HU-SYNC-008) llega al motor: al armarse con lo guardado y en cada cambio
// de la pantalla de sincronización.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/modo_ahorro_providers.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/features/sincronizacion/data/repositories/modo_ahorro_repository_impl.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';

/// La DB «abierta» sin cifrado ni helper: el motor solo necesita el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo()));
  tearDown(() => db.close());

  ProviderContainer armar({required bool guardado}) {
    final contenedor = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(db)),
        transporteSyncProvider.overrideWithValue(FakeSyncTransport()),
        modoAhorroInicialProvider.overrideWithValue(guardado),
        modoAhorroRepositoryProvider.overrideWithValue(
          ModoAhorroRepositoryEnMemoria(activo: guardado),
        ),
      ],
    );
    addTearDown(contenedor.dispose);
    contenedor.listen(modoAhorroProvider, (_, _) {});
    return contenedor;
  }

  test('should start the engine with the saving mode that was saved', () {
    expect(armar(guardado: true).read(motorSyncProvider)!.dataSaver, isTrue);
    expect(armar(guardado: false).read(motorSyncProvider)!.dataSaver, isFalse);
  });

  test('should tell the engine every change of the saving mode', () async {
    final contenedor = armar(guardado: false);
    final motor = contenedor.read(motorSyncProvider)!;

    await contenedor.read(modoAhorroProvider.notifier).cambiar(activo: true);
    expect(motor.dataSaver, isTrue);

    await contenedor.read(modoAhorroProvider.notifier).cambiar(activo: false);
    expect(motor.dataSaver, isFalse);
  });

  test('should keep the same engine when the saving mode changes', () async {
    final contenedor = armar(guardado: false);
    final motor = contenedor.read(motorSyncProvider)!;

    await contenedor.read(modoAhorroProvider.notifier).cambiar(activo: true);

    expect(contenedor.read(motorSyncProvider), same(motor));
  });
}
