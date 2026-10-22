// Después del refresh del token el motor vuelve a intentar (#373, P4). El colportor vuelve a la app
// con el token vencido: el primer ciclo recibe 401 y todo queda `PENDING`. `supabase_flutter`
// refresca el token, pero nadie volvía a disparar el ciclo. Ahora `cicloDeVidaSyncProvider`
// escucha `onAuthStateChange` y, ante `tokenRefreshed`, dispara un ciclo.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_engine/testing.dart';

import '../../../helpers/logger_mudo.dart';

/// La DB «abierta» sin cifrado ni helper: el motor solo necesita el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase _db;

  @override
  AppDatabase? build() => _db;
}

AuthState _cambio(AuthChangeEvent evento) => AuthState(evento, null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeSyncTransport servidor;
  late StreamController<AuthState> sesion;
  late ProviderContainer contenedor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    sesion = StreamController<AuthState>.broadcast();
    contenedor = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(db)),
        transporteSyncProvider.overrideWithValue(servidor),
        cambiosDeSesionSyncProvider.overrideWithValue(sesion.stream),
      ],
    );
  });

  tearDown(() async {
    contenedor.dispose();
    await sesion.close();
    await db.close();
  });

  /// Espera (en tiempo real) a que el servidor haya recibido al menos [n] pulls.
  Future<void> esperarPulls(int n) async {
    for (var i = 0; i < 200 && servidor.pulls.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(servidor.pulls.length, greaterThanOrEqualTo(n), reason: 'el ciclo no llegó al servidor');
  }

  /// Da tiempo a que un ciclo (que no debería existir) se manifieste.
  Future<void> dejarPasar() => Future<void>.delayed(const Duration(milliseconds: 150));

  /// Arma el ciclo de vida (lo que hace la pantalla principal) y espera el ciclo de arranque.
  Future<void> armar() async {
    contenedor.listen(cicloDeVidaSyncProvider, (_, _) {});
    await esperarPulls(1);
    await dejarPasar();
  }

  group('refresh del token dispara el ciclo', () {
    test('tokenRefreshed: vuelve a subir y bajar, sin esperar al próximo resume', () async {
      await armar();
      final antes = servidor.pulls.length;

      sesion.add(_cambio(AuthChangeEvent.tokenRefreshed));

      await esperarPulls(antes + 1);
    });

    test('el 401 del primer ciclo no deja la cola esperando: el refresh la retoma', () async {
      servidor.failWith(401, code: 'JWT_EXPIRED');
      await armar();
      // El ciclo de arranque rebotó con 401: ese intento quedó anotado y nada más corrió.
      final despuesDelRebote = servidor.pulls.length;

      sesion.add(_cambio(AuthChangeEvent.tokenRefreshed));

      await esperarPulls(despuesDelRebote + 1);
    });

    test(
      'dos refrescos seguidos (con el ciclo del primero terminado) disparan dos ciclos',
      () async {
        await armar();
        final antes = servidor.pulls.length;

        sesion.add(_cambio(AuthChangeEvent.tokenRefreshed));
        await esperarPulls(antes + 1);
        await dejarPasar();
        sesion.add(_cambio(AuthChangeEvent.tokenRefreshed));

        await esperarPulls(antes + 2);
      },
    );

    test(
      'un error en el flujo de la sesión no lo mata: el siguiente refresh igual dispara',
      () async {
        await armar();
        final antes = servidor.pulls.length;

        sesion.addError(StateError('flujo roto'));
        await dejarPasar();
        sesion.add(_cambio(AuthChangeEvent.tokenRefreshed));

        await esperarPulls(antes + 1);
      },
    );
  });

  group('lo que no es un refresh no dispara nada', () {
    for (final evento in [
      AuthChangeEvent.initialSession,
      AuthChangeEvent.signedIn,
      AuthChangeEvent.userUpdated,
      AuthChangeEvent.signedOut,
      AuthChangeEvent.passwordRecovery,
    ]) {
      test('${evento.name}: ningún ciclo nuevo', () async {
        await armar();
        final antes = servidor.pulls.length;

        sesion.add(_cambio(evento));
        await dejarPasar();

        expect(servidor.pulls.length, antes);
      });
    }
  });

  test(
    'al soltar el ciclo de vida (se cierra la sesión) un refresh tardío no dispara nada',
    () async {
      final suscripcion = contenedor.listen(cicloDeVidaSyncProvider, (_, _) {});
      await esperarPulls(1);
      await dejarPasar();
      final antes = servidor.pulls.length;

      suscripcion.close();
      contenedor.invalidate(cicloDeVidaSyncProvider);
      await dejarPasar();
      sesion.add(_cambio(AuthChangeEvent.tokenRefreshed));
      await dejarPasar();

      expect(servidor.pulls.length, antes);
      expect(sesion.hasListener, isFalse, reason: 'quedó una escucha viva sobre la sesión');
    },
  );

  test(
    'sin Supabase configurado el flujo de la sesión está vacío y el ciclo de vida arma igual',
    () async {
      final sinSupabase = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(() => _DbFija(db)),
          transporteSyncProvider.overrideWithValue(servidor),
        ],
      );
      addTearDown(sinSupabase.dispose);

      expect(await sinSupabase.read(cambiosDeSesionSyncProvider).isEmpty, isTrue);
      sinSupabase.listen(cicloDeVidaSyncProvider, (_, _) {});
    },
  );
}
