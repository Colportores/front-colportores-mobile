// El cableado del backup (#185, HU-SYNC-005): el motor de la app se arma con el `BackupService` sobre
// la DB, la DEK del almacén y el Drive de la persona. Sin Drive conectado (tests, demo, sin sesión)
// el backup falla limpio, sin pedirle nada al almacén seguro ni a la red.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/adapters.dart';

import '../../../helpers/logger_mudo.dart';

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
  late ProviderContainer contenedor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    contenedor = ProviderContainer(overrides: [dbLocalProvider.overrideWith(() => _DbFija(db))]);
  });

  tearDown(() async {
    contenedor.dispose();
    await db.close();
  });

  test('el motor de la app trae el backup armado', () {
    final motor = contenedor.read(motorSyncProvider)!;

    expect(() => motor.backup, returnsNormally);
  });

  test('sin Drive conectado el backup no sube nada: falla por falta de token', () async {
    final motor = contenedor.read(motorSyncProvider)!;

    await expectLater(motor.backup.backupNow(), throwsA(isA<ArchiveSinToken>()));
  });

  test('la verificación sin Drive tampoco rompe: lo avisa con la misma falla', () async {
    final motor = contenedor.read(motorSyncProvider)!;

    await expectLater(motor.backup.verifyIntegrity(), throwsA(isA<ArchiveSinToken>()));
  });
}
