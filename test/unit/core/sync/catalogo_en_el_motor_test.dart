// El cableado del catálogo (#180): el motor de la app se arma con Realtime (HU-SYNC-003) y, al
// arrancar la sesión, el ciclo de vida baja el catálogo entero en segundo plano (HU-CAT-007: la
// primera carga), sin que la consulta de precios espere.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeRealtime realtime;
  late ProviderContainer contenedor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    realtime = FakeRealtime();
    contenedor = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(db)),
        transporteSyncProvider.overrideWithValue(servidor),
        realtimeSyncProvider.overrideWithValue(realtime),
      ],
    );
  });

  tearDown(() async {
    contenedor.dispose();
    await realtime.dispose();
    await db.close();
  });

  test(
    'sin Supabase configurado (tests, demo) no hay Realtime: el motor sigue con los triggers',
    () {
      final sinOverride = ProviderContainer(
        overrides: [dbLocalProvider.overrideWith(() => _DbFija(db))],
      );
      addTearDown(sinOverride.dispose);

      expect(sinOverride.read(realtimeSyncProvider), isNull);
      expect(sinOverride.read(motorSyncProvider), isNotNull);
    },
  );

  test('el motor se suscribe a Realtime en producto y en los precios de la ciudad', () {
    contenedor.read(motorSyncProvider);

    expect(realtime.subscriptions.single, unorderedEquals(['producto', 'precio_por_ciudad']));
  });

  test('al arrancar la sesión baja el catálogo en segundo plano, con el precio general', () async {
    servidor
      ..seed('producto', [
        {
          'id': 'pro-1',
          'nombre': 'El Conflicto de los Siglos',
          'descripcion': null,
          'tipo': 'LIBRO',
          'es_bonificable': true,
          'es_misionero': false,
          'precio_base_compra': null,
          'casa_editora': null,
          'imagen_url': null,
          'created_at': '2026-10-20T12:00:00+00:00',
          'updated_at': '2026-10-20T12:00:00+00:00',
          'created_by': null,
          'deleted_at': null,
          'sync_version': 1,
        },
      ])
      ..seed('precio_general', [
        {
          'id': 'pg-1',
          'producto_id': 'pro-1',
          'coleccion_id': null,
          'precio_venta': 45000,
          'valido_desde': '2026-01-01',
          'valido_hasta': null,
          'created_at': '2026-10-20T12:00:00+00:00',
          'updated_at': '2026-10-20T12:00:00+00:00',
          'created_by': null,
          'deleted_at': null,
          'sync_version': 1,
        },
      ])
      ..seed('parametro_global', [
        {
          'id': 'par-1',
          'clave': 'dias_antiguedad_precios',
          'valor': 21,
          'created_at': '2026-10-20T12:00:00+00:00',
          'updated_at': '2026-10-20T12:00:00+00:00',
          'created_by': null,
          'deleted_at': null,
          'sync_version': 1,
        },
      ]);

    contenedor.listen(cicloDeVidaSyncProvider, (_, _) {});
    for (var i = 0; i < 300; i++) {
      if ((await db.select(db.preciosGenerales).get()).isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect((await db.select(db.productos).getSingle()).nombre, 'El Conflicto de los Siglos');
    expect((await db.select(db.preciosGenerales).getSingle()).precioVenta, 45000);
    // Los días del aviso de precios viejos bajan con el catálogo (backend-supabase 0070).
    expect((await db.select(db.parametrosGlobales).getSingle()).valor, 21);
  });
}
