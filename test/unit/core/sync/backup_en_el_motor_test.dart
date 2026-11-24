// El cableado del backup (#185, HU-SYNC-005): el motor de la app se arma con el `BackupService` sobre
// la DB, la DEK del almacén y el Drive de la persona. Sin Drive conectado (tests, demo, sin sesión)
// el backup falla limpio, sin pedirle nada al almacén seguro ni a la red.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../helpers/logger_mudo.dart';

/// Si el asistente de recuperación está pendiente (abierto) o no, a mano.
class _Pendiente extends RecuperacionPendiente {
  _Pendiente(this._valor);

  final bool _valor;

  @override
  Future<bool> build() async => _valor;

  void cambiar(bool valor) => state = AsyncData(valor);
}

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

  group('«Motor vivo» (HU-SYNC-006): con el asistente de recuperación abierto no hay motor', () {
    ProviderContainer conAsistente({required bool habilitado, required bool pendiente}) {
      final c = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(() => _DbFija(db)),
          asistenteDeRecuperacionHabilitadoProvider.overrideWithValue(habilitado),
          recuperacionPendienteProvider.overrideWith(() => _Pendiente(pendiente)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('asistente abierto: el motor de la app no existe, para que nada escuche la DB', () async {
      final c = conAsistente(habilitado: true, pendiente: true);
      await c.read(recuperacionPendienteProvider.future);

      expect(c.read(motorSyncProvider), isNull);
    });

    test(
      'asistente apagado en la app (tests, demo): el motor se arma aunque esté «pendiente»',
      () async {
        final c = conAsistente(habilitado: false, pendiente: true);
        await c.read(recuperacionPendienteProvider.future);

        expect(c.read(motorSyncProvider), isNotNull);
      },
    );

    test('al cerrarse el asistente, el motor vuelve; al reabrirse, se cierra otra vez', () async {
      final c = conAsistente(habilitado: true, pendiente: true);
      await c.read(recuperacionPendienteProvider.future);
      final escuchas = <SyncEngine?>[];
      c.listen(motorSyncProvider, (_, nuevo) => escuchas.add(nuevo), fireImmediately: true);
      expect(escuchas.single, isNull);

      (c.read(recuperacionPendienteProvider.notifier) as _Pendiente).cambiar(false);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(motorSyncProvider), isNotNull, reason: 'la persona terminó: la app sincroniza');

      (c.read(recuperacionPendienteProvider.notifier) as _Pendiente).cambiar(true);
      await Future<void>.delayed(Duration.zero);
      expect(
        c.read(motorSyncProvider),
        isNull,
        reason: '«Recuperar mi respaldo» desde Configuración',
      );
    });

    test('sin asistente pendiente, el motor es el de siempre', () async {
      final c = conAsistente(habilitado: true, pendiente: false);
      await c.read(recuperacionPendienteProvider.future);

      expect(c.read(motorSyncProvider), isNotNull);
    });
  });
}
