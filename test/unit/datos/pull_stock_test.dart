// HU-STK-004 de punta a punta (#545), con el código real de los dos lados de la frontera: el motor
// baja el delta de un servidor falso que pagina y se cae como el de verdad, y lo que baja entra por
// `DriftLocalStore` a la DB de la app. El stock es una réplica de solo lectura: el pull lo llena y
// nada del teléfono lo encola.
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

Map<String, Object?> _stock(String id, {int disponible = 10, int version = 1, String? baja}) => {
  'id': id,
  'usuario_id': 'col-1',
  'producto_id': 'pro-$id',
  'cantidad_disponible': disponible,
  'cantidad_reservada': 0,
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-20T12:00:00+00:00',
  'created_by': null,
  'deleted_at': baja,
  'sync_version': version,
};

/// El servidor de verdad entrega el delta en páginas ([porPagina] filas) y se puede caer entre dos.
final class _ServidorPaginado implements SyncTransport {
  _ServidorPaginado(this._real, {required this.porPagina});

  final FakeSyncTransport _real;
  final int porPagina;
  final paginas = <String?>[];
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
  late FakeConnectivityPort red;
  late SyncEngine motor;

  SyncEngine armar({SyncTransport? transporte}) => SyncEngine(
    specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
    transport: transporte ?? servidor,
    jobs: DriftJobStore(db),
    store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
    connectivity: red,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    red = FakeConnectivityPort();
    motor = armar();
  });
  tearDown(() async {
    await motor.dispose();
    await red.dispose();
    await db.close();
  });

  Future<Map<String, int>> cantidades() async => {
    for (final s in await db.select(db.stocks).get()) s.id: s.cantidadDisponible,
  };

  test('primera carga: baja el stock del colportor, con la cantidad negativa también', () async {
    servidor.seed('stock', [_stock('a', disponible: 10), _stock('b', disponible: -2)]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 2);
    expect(await cantidades(), {'a': 10, 'b': -2});
  });

  test('el pull no encola nada: el stock no sube nunca', () async {
    servidor.seed('stock', [_stock('a')]);

    await motor.syncNow();

    expect(await db.select(db.syncQueue).get(), isEmpty);
  });

  test('pull idempotente: el segundo no aplica cambios y deja todo igual', () async {
    servidor.seed('stock', [_stock('a'), _stock('b')]);
    await motor.syncNow();

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 0);
    expect(await cantidades(), {'a': 10, 'b': 10});
  });

  test('una entrega que el servidor descontó baja solo esa fila con la cantidad nueva', () async {
    servidor.seed('stock', [_stock('a', disponible: 10), _stock('b', disponible: 5)]);
    await motor.syncNow();
    servidor.seed('stock', [_stock('a', disponible: 7, version: 2)]);

    final r = await motor.syncNow();

    expect(r.pulled, 1);
    expect(await cantidades(), {'a': 7, 'b': 5});
    expect(await db.select(db.stocks).get(), hasLength(2));
  });

  test('una baja lógica baja como tombstone y la fila queda marcada', () async {
    servidor.seed('stock', [_stock('a')]);
    await motor.syncNow();
    servidor.seed('stock', [_stock('a', version: 2, baja: '2026-10-28T10:00:00+00:00')]);

    await motor.syncNow();

    expect((await db.select(db.stocks).getSingle()).deletedAt, DateTime.utc(2026, 10, 28, 10));
  });

  test('error de red a mitad: no aplica nada y el próximo ciclo lo trae', () async {
    servidor.seed('stock', [_stock('a')]);
    servidor.failTransient();

    final cortado = await motor.syncNow();

    expect(cortado.failure, isNotNull);
    expect(await cantidades(), isEmpty);

    final siguiente = await motor.syncNow();

    expect(siguiente.ok, isTrue);
    expect(await cantidades(), {'a': 10});
  });

  test('un delta grande se pagina; si se corta entre páginas, sigue donde quedó', () async {
    servidor.seed('stock', [for (var i = 1; i <= 5; i++) _stock('s$i')]);
    final paginado = _ServidorPaginado(servidor, porPagina: 2)..cortarEnLaPagina = 2;
    await motor.dispose();
    motor = armar(transporte: paginado);

    final cortado = await motor.syncNow();

    expect(cortado.failure, isNotNull);
    expect(await db.select(db.stocks).get(), hasLength(2));

    paginado.cortarEnLaPagina = null;
    paginado.paginas.clear();
    final siguiente = await motor.syncNow();

    expect(siguiente.ok, isTrue);
    expect(paginado.paginas.first, isNotNull);
    expect(await db.select(db.stocks).get(), hasLength(5));
  });

  test('un servidor que todavía no publica el stock no rompe el pull de lo demás', () async {
    // Sin `seed('stock', …)`: el servidor no tiene filas (o no conoce la entidad) y el resto sigue.
    servidor.seed('producto', [
      {
        'id': 'pro-1',
        'nombre': 'Libro',
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
    ]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(await db.select(db.productos).get(), hasLength(1));
    expect(await db.select(db.stocks).get(), isEmpty);
  });
}
