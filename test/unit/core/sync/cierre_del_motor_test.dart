// El cierre del motor al tirarse la raíz (HU-AUTH-006, HU-SYNC-006): `motor.dispose()` no espera al
// ciclo que ya está corriendo, y ese ciclo sigue usando la DB. `cerrarElMotor` lo espera, y
// `CierreDeLaRaiz.alTirar` espera a `cerrarElMotor` antes de cerrar la base.
import 'dart:async';

import 'package:colportores_mobile/core/arranque/cierre_de_la_raiz.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';

/// Un servidor al que la bajada le tarda lo que el test quiera.
class _TransporteDetenible extends FakeSyncTransport {
  final puerta = Completer<void>();
  final bajadaIniciada = Completer<void>();

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) async {
    if (!bajadaIniciada.isCompleted) bajadaIniciada.complete();
    await puerta.future;
    return super.pull(entities: entities, watermark: watermark, limit: limit);
  }
}

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase _db;

  @override
  AppDatabase? build() => _db;
}

SyncEngine _motorCon(SyncTransport transporte) => SyncEngine(
  specs: SpecRegistry([SyncSpec.pull('producto')], allEntities: const {'producto'}),
  transport: transporte,
  jobs: InMemoryJobStore(),
  store: InMemoryLocalStore(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('cerrarElMotor', () {
    test('espera a que termine el ciclo en curso antes de volver', () async {
      final transporte = _TransporteDetenible();
      final motor = _motorCon(transporte);
      final ciclo = motor.syncNow();
      await transporte.bajadaIniciada.future;

      var cerrado = false;
      final cierre = cerrarElMotor(motor).then((_) => cerrado = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cerrado, isFalse, reason: 'el ciclo sigue usando la DB: el cierre espera');

      transporte.puerta.complete();
      await cierre;
      expect((await ciclo).skipped, isFalse, reason: 'el ciclo terminó, no se lo cortó');
      expect(cerrado, isTrue);
      expect(() => motor.statusNow(), throwsStateError, reason: 'el motor quedó dado de baja');
    });

    test('un ciclo que no termina no deja la app esperando para siempre', () async {
      final transporte = _TransporteDetenible();
      final motor = _motorCon(transporte);
      unawaited(motor.syncNow());
      await transporte.bajadaIniciada.future;

      await cerrarElMotor(motor, espera: const Duration(milliseconds: 50));

      expect(() => motor.statusNow(), throwsStateError);
      transporte.puerta.complete();
    });

    test('sin ciclo en curso vuelve enseguida', () async {
      final motor = _motorCon(FakeSyncTransport());

      await cerrarElMotor(motor);

      expect(() => motor.statusNow(), throwsStateError);
    });

    test('lo que se tire durante la espera no lanza hacia afuera', () async {
      final motor = _motorCon(FakeSyncTransport());
      await motor.dispose();

      await expectLater(cerrarElMotor(motor), completes);
    });
  });

  group('motorSyncProvider al tirarse la raíz', () {
    late AppDatabase db;
    late CierreDeLaRaiz cierre;
    late ProviderContainer contenedor;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      cierre = CierreDeLaRaiz(logger: loggerMudo());
      contenedor = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(() => _DbFija(db)),
          cierreDeLaRaizProvider.overrideWithValue(cierre),
        ],
      );
    });

    tearDown(() async {
      contenedor.dispose();
      await db.close();
    });

    test('el cierre del motor queda anotado y alTirar lo espera', () async {
      final motor = contenedor.read(motorSyncProvider)!;

      contenedor.dispose();
      await cierre.alTirar();

      expect(() => motor.statusNow(), throwsStateError, reason: 'el motor viejo quedó cerrado');
    });
  });
}
