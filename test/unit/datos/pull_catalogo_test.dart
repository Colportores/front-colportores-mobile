// HU-SYNC-002, HU-SYNC-003 y HU-CAT-007 de punta a punta (#180), con el código real de los dos lados
// de la frontera: el motor baja el delta de un servidor falso que pagina y se cae como el de
// verdad, y lo que baja entra por `DriftLocalStore` a la DB de la app. Realtime es un timbre: el
// evento no trae datos, el motor baja el delta.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

Map<String, Object?> _auditoria([int version = 1]) => {
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-20T12:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': version,
};

Map<String, Object?> _producto(String id, {String? nombre, int version = 1}) => {
  'id': id,
  'nombre': nombre ?? 'Libro $id',
  'descripcion': null,
  'tipo': 'LIBRO',
  'es_bonificable': true,
  'es_misionero': false,
  'precio_base_compra': 18000,
  'casa_editora': null,
  'imagen_url': null,
  ..._auditoria(version),
};

Map<String, Object?> _coleccion(String id) => {
  'id': id,
  'nombre': 'Pack $id',
  'libros_a_elegir': 0,
  ..._auditoria(),
};

Map<String, Object?> _componente(String id, {int cantidad = 1}) => {
  'id': id,
  'producto_id': 'pro-1',
  'coleccion_id': 'col-1',
  'cantidad': cantidad,
  ..._auditoria(),
};

Map<String, Object?> _excepcion(String id, {int precio = 42000, int version = 1}) => {
  'id': id,
  'producto_id': 'pro-1',
  'coleccion_id': null,
  'campania_ciudad_id': 'cc-1',
  'precio_venta': precio,
  'valido_desde': '2026-10-27',
  'valido_hasta': null,
  ..._auditoria(version),
};

Map<String, Object?> _general(String id, {int precio = 45000}) => {
  'id': id,
  'producto_id': 'pro-1',
  'coleccion_id': null,
  'precio_venta': precio,
  'valido_desde': '2026-01-01',
  'valido_hasta': null,
  ..._auditoria(),
};

/// El servidor de verdad entrega el delta en páginas ([porPagina] filas) y se puede caer entre dos.
final class _ServidorPaginado implements SyncTransport {
  _ServidorPaginado(this._real, {required this.porPagina});

  final FakeSyncTransport _real;
  final int porPagina;

  /// Las páginas pedidas, en orden, con su watermark de entrada.
  final paginas = <String?>[];

  /// El número (desde 1) de la página que se corta, o `null`.
  int? cortarEnLaPagina;

  @override
  Future<PushResult> push(PushBatch batch) => _real.push(batch);

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) async {
    paginas.add(watermark);
    if (paginas.length == cortarEnLaPagina) {
      throw const TransportFailure(FailureKind.transient, message: 'se cayó la red');
    }
    return _real.pull(entities: entities, watermark: watermark, limit: porPagina);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeRealtime realtime;
  late FakeConnectivityPort red;
  late SyncEngine motor;

  SyncEngine armar({SyncTransport? transporte}) => SyncEngine(
    specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
    transport: transporte ?? servidor,
    jobs: DriftJobStore(db),
    store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
    connectivity: red,
    realtime: realtime,
    realtimeDebounce: const Duration(milliseconds: 5),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    realtime = FakeRealtime();
    red = FakeConnectivityPort();
    motor = armar();
  });
  tearDown(() async {
    await motor.dispose();
    await realtime.dispose();
    await red.dispose();
    await db.close();
  });

  void sembrarCatalogo() {
    servidor
      ..seed('producto', [_producto('pro-1'), _producto('pro-2')])
      ..seed('coleccion', [_coleccion('col-1')])
      ..seed('producto_coleccion', [_componente('pc-1', cantidad: 2)])
      ..seed('precio_por_ciudad', [_excepcion('ppc-1')])
      ..seed('precio_general', [_general('pg-1')]);
  }

  Future<int> contar() async =>
      (await db.select(db.productos).get()).length +
      (await db.select(db.colecciones).get()).length +
      (await db.select(db.productoColecciones).get()).length +
      (await db.select(db.preciosPorCiudad).get()).length +
      (await db.select(db.preciosGenerales).get()).length;

  Future<void> esperarHasta(Future<bool> Function() condicion) async {
    final limite = DateTime.now().add(const Duration(seconds: 5));
    while (!await condicion()) {
      if (DateTime.now().isAfter(limite)) fail('la condición no se cumplió en 5 s');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<int?> precioDeLaCiudad() async =>
      (await db.select(db.preciosPorCiudad).getSingleOrNull())?.precioVenta;

  group('pull delta (HU-SYNC-002, HU-CAT-007)', () {
    test('primera carga: baja todo el catálogo, con el precio general y el de la ciudad', () async {
      sembrarCatalogo();

      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      expect(r.pulled, 6);
      expect(await db.select(db.productos).get(), hasLength(2));
      expect(await db.select(db.colecciones).get(), hasLength(1));
      expect((await db.select(db.productoColecciones).getSingle()).cantidad, 2);
      expect((await db.select(db.preciosPorCiudad).getSingle()).precioVenta, 42000);
      expect((await db.select(db.preciosGenerales).getSingle()).precioVenta, 45000);
    });

    test('pull idempotente: el segundo no aplica cambios y deja todo igual', () async {
      sembrarCatalogo();
      await motor.syncNow();
      final marca = await DriftLocalStore(
        db,
        entidades: entidadesQueEscribeElMotor,
      ).watermarkOf('replica');

      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      expect(r.pulled, 0);
      expect(await contar(), 6);
      expect(
        await DriftLocalStore(db, entidades: entidadesQueEscribeElMotor).watermarkOf('replica'),
        marca,
      );
    });

    test('un cambio en el servidor baja solo ese delta y pisa la fila', () async {
      sembrarCatalogo();
      await motor.syncNow();
      servidor.seed('precio_por_ciudad', [_excepcion('ppc-1', precio: 39000, version: 2)]);

      final r = await motor.syncNow();

      expect(r.pulled, 1);
      expect(await precioDeLaCiudad(), 39000);
      expect(await db.select(db.preciosPorCiudad).get(), hasLength(1));
    });

    test(
      'error de red a mitad: no aplica nada, el watermark queda y el próximo ciclo lo trae',
      () async {
        sembrarCatalogo();
        servidor.failTransient();

        final cortado = await motor.syncNow();

        expect(cortado.failure, isNotNull);
        expect(await contar(), 0);
        expect(
          await DriftLocalStore(db, entidades: entidadesQueEscribeElMotor).watermarkOf('replica'),
          isNull,
        );

        final siguiente = await motor.syncNow();

        expect(siguiente.ok, isTrue);
        expect(await contar(), 6);
      },
    );

    test('un delta grande se pagina; si se corta entre páginas, sigue donde quedó', () async {
      for (var i = 1; i <= 5; i++) {
        servidor.seed('producto', [_producto('p-$i')]);
      }
      servidor.seed('precio_por_ciudad', [_excepcion('ppc-1')]);
      final paginado = _ServidorPaginado(servidor, porPagina: 2)..cortarEnLaPagina = 2;
      await motor.dispose();
      motor = armar(transporte: paginado);

      final cortado = await motor.syncNow();

      expect(cortado.failure, isNotNull);
      // La primera página entró entera y con su watermark; la segunda nunca llegó.
      expect(await db.select(db.productos).get(), hasLength(2));
      expect(
        await DriftLocalStore(db, entidades: entidadesQueEscribeElMotor).watermarkOf('replica'),
        isNotNull,
      );

      paginado.cortarEnLaPagina = null;
      paginado.paginas.clear();
      final siguiente = await motor.syncNow();

      expect(siguiente.ok, isTrue);
      // Retoma desde el watermark de la primera página: no vuelve a pedir lo que ya tiene.
      expect(paginado.paginas.first, isNotNull);
      expect(await db.select(db.productos).get(), hasLength(5));
      expect(await db.select(db.preciosPorCiudad).get(), hasLength(1));
      expect(siguiente.pulled, 4);
    });

    test('una fila que la DB rechaza: el delta no se aplica, el watermark no avanza y no queda '
        'nada a medias', () async {
      servidor
        ..seed('producto', [_producto('pro-1')])
        ..seed('producto_coleccion', [_componente('pc-1', cantidad: 0)]);

      await expectLater(motor.syncNow(), throwsA(anything));

      expect(await contar(), 0);
      expect(
        await DriftLocalStore(db, entidades: entidadesQueEscribeElMotor).watermarkOf('replica'),
        isNull,
      );

      // El servidor corrige la fila: el próximo ciclo entra completo.
      servidor.seed('producto_coleccion', [_componente('pc-1', cantidad: 2)]);
      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      expect(await contar(), 2);
    });

    test('el servidor aún no publica el precio general: el pull igual baja el resto', () async {
      servidor
        ..seed('producto', [_producto('pro-1')])
        ..seed('precio_por_ciudad', [_excepcion('ppc-1')]);

      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      expect(await contar(), 2);
      expect(await db.select(db.preciosGenerales).get(), isEmpty);
      // El motor sí lo pide: el día que el servidor lo registre, baja solo.
      expect(servidor.pulls.last.entities, contains('precio_general'));
    });
  });

  group('realtime (HU-SYNC-003)', () {
    test('se suscribe a producto y a los precios de la ciudad, y a nada más', () {
      expect(realtime.subscriptions.single, unorderedEquals(['producto', 'precio_por_ciudad']));
    });

    test('un cambio de precio llega por el evento y la pantalla lo ve sin pull manual', () async {
      sembrarCatalogo();
      await motor.syncNow();
      final precios = <int>[];
      final suscripcion = db
          .select(db.preciosPorCiudad)
          .watch()
          .listen((filas) => precios.addAll(filas.map((f) => f.precioVenta)));
      addTearDown(suscripcion.cancel);
      await esperarHasta(() async => precios.isNotEmpty);

      servidor.seed('precio_por_ciudad', [_excepcion('ppc-1', precio: 39000, version: 2)]);
      realtime.emit('precio_por_ciudad');

      await esperarHasta(() async => precios.contains(39000));
      expect(await precioDeLaCiudad(), 39000);
    });

    test('un producto nuevo llega por el evento', () async {
      sembrarCatalogo();
      await motor.syncNow();
      servidor.seed('producto', [_producto('pro-3', nombre: 'Novedad')]);

      realtime.emit('producto');

      await esperarHasta(() async => (await db.select(db.productos).get()).length == 3);
    });

    test('cincuenta eventos seguidos son un solo pull', () async {
      sembrarCatalogo();
      await motor.syncNow();
      final antes = servidor.pulls.length;
      servidor.seed('precio_por_ciudad', [_excepcion('ppc-1', precio: 30000, version: 2)]);

      for (var i = 0; i < 50; i++) {
        realtime.emit('precio_por_ciudad');
      }
      await esperarHasta(() async => await precioDeLaCiudad() == 30000);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(servidor.pulls.length - antes, 1);
    });

    test('con el ahorro de datos y sin Wi-Fi, el evento igual baja el cambio urgente', () async {
      sembrarCatalogo();
      await motor.syncNow();
      motor.setDataSaver(true);
      red.goMobile();
      servidor.seed('precio_por_ciudad', [_excepcion('ppc-1', precio: 31000, version: 2)]);

      realtime.emit('precio_por_ciudad');

      await esperarHasta(() async => await precioDeLaCiudad() == 31000);
    });

    test('estuve sin red: los eventos que se perdieron los recupera el pull al volver', () async {
      sembrarCatalogo();
      await motor.syncNow();
      red.goOffline();
      servidor
        ..offline()
        ..seed('precio_por_ciudad', [_excepcion('ppc-1', precio: 28000, version: 2)]);
      // El evento se perdió: sin red no llegó. Nada cambia en el teléfono.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await precioDeLaCiudad(), 42000);

      servidor.online();
      red.goOnline();

      await esperarHasta(() async => await precioDeLaCiudad() == 28000);
    });

    test('un evento con el servidor caído no rompe el motor: el próximo ciclo lo trae', () async {
      sembrarCatalogo();
      await motor.syncNow();
      servidor
        ..seed('precio_por_ciudad', [_excepcion('ppc-1', precio: 27000, version: 2)])
        ..failTransient();

      realtime.emit('precio_por_ciudad');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await precioDeLaCiudad(), 42000);

      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      expect(await precioDeLaCiudad(), 27000);
    });
  });
}
