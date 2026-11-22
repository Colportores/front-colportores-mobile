// La cola no guarda para siempre los envíos confirmados (#188): `PurgaDeLaCola` y su cableado en
// `cicloDeVidaSyncProvider` (al arrancar y cada vez que termina un ciclo bien), sobre una DB real
// en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/purga_de_la_cola.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

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

  group('PurgaDeLaCola', () {
    test('llama a la purga una vez por corrida', () async {
      var llamadas = 0;
      final purga = PurgaDeLaCola(() async => ++llamadas);

      await purga.correr();
      await purga.correr();

      expect(llamadas, 2);
      expect(purga.corriendo, isFalse);
    });

    test('dos corridas a la vez hacen una sola purga', () async {
      final compuerta = Completer<int>();
      var llamadas = 0;
      final purga = PurgaDeLaCola(() {
        llamadas++;
        return compuerta.future;
      });

      final primera = purga.correr();
      final segunda = purga.correr();
      expect(purga.corriendo, isTrue);
      compuerta.complete(3);
      await Future.wait([primera, segunda]);

      expect(llamadas, 1);
      expect(purga.corriendo, isFalse);
    });

    test('si la purga falla no lanza y la siguiente corrida vuelve a intentar', () async {
      var llamadas = 0;
      final purga = PurgaDeLaCola(() async {
        llamadas++;
        if (llamadas == 1) throw StateError('base cerrada');
        return 0;
      });

      await purga.correr();
      expect(purga.corriendo, isFalse, reason: 'una falla no deja la purga trabada');
      await purga.correr();

      expect(llamadas, 2);
    });
  });

  group('con el motor y una DB real', () {
    late AppDatabase db;
    late FakeSyncTransport servidor;
    late ProviderContainer contenedor;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      servidor = FakeSyncTransport();
      contenedor = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(() => _DbFija(db)),
          transporteSyncProvider.overrideWithValue(servidor),
        ],
      );
    });

    tearDown(() async {
      contenedor.dispose();
      await db.close();
    });

    /// Deja un envío ya confirmado (`DONE`) hace [antiguedad]; devuelve su `client_op_id`.
    Future<String> sembrarDone(String opId, Duration antiguedad) async {
      final cola = DriftJobStore(db);
      await cola.append(
        SyncJob(
          clientOpId: opId,
          entity: 'venta',
          op: Op.insert,
          payload: {'id': opId},
          createdAt: DateTime.now().toUtc().subtract(antiguedad),
        ),
      );
      final tomados = await cola.claimPending(limit: 10);
      await cola.markDone([
        for (final q in tomados) q.id,
      ], at: DateTime.now().toUtc().subtract(antiguedad));
      return opId;
    }

    Future<Set<String>> opsEnLaCola() async {
      final filas = await db.select(db.syncQueue).get();
      return {for (final f in filas) f.clientOpId};
    }

    Future<void> esperarA(bool Function() condicion, String motivo) async {
      for (var i = 0; i < 300 && !condicion(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condicion(), isTrue, reason: motivo);
    }

    test('al arrancar: un DONE de 8 días desaparece y uno de 6 días 23 h queda', () async {
      final viejo = await sembrarDone('op-viejo', const Duration(days: 8));
      final reciente = await sembrarDone('op-reciente', const Duration(days: 6, hours: 23));
      expect(await opsEnLaCola(), {viejo, reciente});

      contenedor.listen(cicloDeVidaSyncProvider, (_, _) {});
      // Con el servidor sin falla, el ciclo de arranque termina bien y el pull llega.
      await esperarA(() => servidor.pulls.isNotEmpty, 'el ciclo de arranque no llegó al servidor');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(await opsEnLaCola(), {reciente});
    });

    test('sin red al arrancar igual se purga: no espera a que un ciclo salga bien', () async {
      servidor.failWith(0, code: 'SIN_RED');
      final viejo = await sembrarDone('op-viejo', const Duration(days: 30));

      contenedor.listen(cicloDeVidaSyncProvider, (_, _) {});
      for (var i = 0; i < 100 && (await opsEnLaCola()).contains(viejo); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(await opsEnLaCola(), isEmpty);
    });

    test('cada vez que un ciclo termina bien se vuelve a purgar', () async {
      contenedor.listen(cicloDeVidaSyncProvider, (_, _) {});
      await esperarA(() => servidor.pulls.isNotEmpty, 'el ciclo de arranque no llegó al servidor');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Después del arranque entra un DONE vencido (el teléfono estuvo días sin purgar).
      final viejo = await sembrarDone('op-vencido', const Duration(days: 9));
      expect(await opsEnLaCola(), {viejo});

      final motor = contenedor.read(motorSyncProvider)!;
      await motor.syncNow();
      for (var i = 0; i < 100 && (await opsEnLaCola()).isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(await opsEnLaCola(), isEmpty);
    });

    test('la purga no toca lo que espera, falló o está en conflicto', () async {
      final cola = DriftJobStore(db);
      final antiguo = DateTime.now().toUtc().subtract(const Duration(days: 40));
      Future<void> agregar(String opId) => cola.append(
        SyncJob(
          clientOpId: opId,
          entity: 'venta',
          op: Op.insert,
          payload: {'id': opId},
          createdAt: antiguo,
        ),
      );
      await agregar('op-invalido');
      await agregar('op-bloqueado');
      final tomados = await cola.claimPending(limit: 10);
      await cola.markInvalid(tomados[0].id, code: 'X');
      await cola.markBlocked(tomados[1].id, code: 'Y');
      servidor.failWith(0, code: 'SIN_RED');
      await agregar('op-pendiente');

      contenedor.listen(cicloDeVidaSyncProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(await opsEnLaCola(), {'op-invalido', 'op-bloqueado', 'op-pendiente'});
    });
  });
}
