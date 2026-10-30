// La réplica local del stock del colportor (HU-STK-004, #545). Lo que baja el pull entra por
// `DriftLocalStore`, columna por columna y por nombre, así que la prueba de que la tabla tiene la
// forma del cloud es doble: toda columna local existe en la fila del servidor, y la fila aplicada
// se lee igual que como viajó. La lectura (`StockLocalDataSource`) solo devuelve el stock vivo del
// colportor.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/stock/data/datasources/stock_local_data_source.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../../helpers/logger_mudo.dart';

/// La fila como la arma `sync.pull` (backend-supabase 0002): todas las columnas de `public.stock`,
/// los `timestamptz` en ISO-8601 con zona y `xmin_w` de más.
Map<String, Object?> _fila(
  String id, {
  String usuario = 'col-1',
  String producto = 'pro-1',
  int disponible = 10,
  int reservada = 0,
  int version = 1,
  String? baja,
}) => {
  'id': id,
  'usuario_id': usuario,
  'producto_id': producto,
  'cantidad_disponible': disponible,
  'cantidad_reservada': reservada,
  'created_at': '2026-10-20T12:00:00.123456+00:00',
  'updated_at': '2026-10-28T09:30:00+00:00',
  'created_by': 'coord-1',
  'deleted_at': baja,
  'sync_version': version,
  'xmin_w': '123456',
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftLocalStore store;
  late StockLocalDataSource lectura;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
    lectura = StockLocalDataSource(db);
  });
  tearDown(() => db.close());

  Future<void> aplicar(List<Map<String, Object?>> filas, {String w = 'w1'}) =>
      store.applyDelta({'stock': filas}, scope: 'replica', watermark: w);

  group('el registro del motor', () {
    final spec = specsDeLaApp.singleWhere((s) => s.entity == 'stock');

    test('stock es una réplica de solo lectura: política pull', () {
      expect(spec.policy, SyncPolicy.pull);
    });

    test('sin Realtime (ADR-012): baja en el ciclo, no al instante', () {
      expect(spec.realtime, isFalse);
    });

    test('la app no la escribe pero el motor sí puede (aplica el delta)', () {
      expect(entidadesQueEscribeElMotor, contains('stock'));
    });
  });

  group('la tabla tiene la forma de la entidad del cloud', () {
    test('toda columna local viene en la fila del servidor', () {
      final tabla = db.allTables.singleWhere((t) => t.actualTableName == 'stock');
      final locales = tabla.$columns.map((c) => c.name).toSet();
      final fila = _fila('stk-1');

      expect(fila.keys.toSet().containsAll(locales), isTrue, reason: 'faltan columnas');
      // Lo único que el servidor manda de más es `xmin_w`, el cursor del delta: no se guarda.
      expect(fila.keys.toSet().difference(locales), {'xmin_w'});
    });

    test('las cantidades, las fechas ISO a epoch ms UTC y la versión', () async {
      await aplicar([_fila('stk-1', disponible: 10, reservada: 2, version: 3)]);

      final s = await db.select(db.stocks).getSingle();
      expect(s.id, 'stk-1');
      expect(s.usuarioId, 'col-1');
      expect(s.productoId, 'pro-1');
      expect(s.cantidadDisponible, 10);
      expect(s.cantidadReservada, 2);
      expect(s.createdAt, DateTime.utc(2026, 10, 20, 12, 0, 0, 123));
      expect(s.updatedAt, DateTime.utc(2026, 10, 28, 9, 30));
      expect(s.createdBy, 'coord-1');
      expect(s.deletedAt, isNull);
      expect(s.syncVersion, 3);
    });

    test('la cantidad disponible puede ser negativa: entregó de más (S46)', () async {
      await aplicar([_fila('stk-1', disponible: -2)]);

      expect((await db.select(db.stocks).getSingle()).cantidadDisponible, -2);
    });

    test('un stock en cero es una fila con cero, no una fila ausente', () async {
      await aplicar([_fila('stk-1', disponible: 0)]);

      expect((await lectura.deProducto('col-1', 'pro-1'))?.cantidadDisponible, 0);
      expect(await lectura.deProducto('col-1', 'pro-9'), isNull);
    });

    test('la reservada nunca es negativa: la tabla rechaza la fila, como el servidor', () async {
      await expectLater(aplicar([_fila('stk-1', reservada: -1)]), throwsA(anything));

      expect(await db.select(db.stocks).get(), isEmpty);
    });
  });

  group('el delta siguiente pisa la fila, nunca la duplica', () {
    test('una entrega que el servidor descontó baja la cantidad nueva', () async {
      await aplicar([_fila('stk-1', disponible: 10)]);

      await aplicar([_fila('stk-1', disponible: 7, version: 2)], w: 'w2');

      final filas = await db.select(db.stocks).get();
      expect(filas, hasLength(1));
      expect([filas.single.cantidadDisponible, filas.single.syncVersion], [7, 2]);
      expect(await store.watermarkOf('replica'), 'w2');
    });

    test('un producto nuevo se suma a los que ya había', () async {
      await aplicar([_fila('stk-1')]);

      await aplicar([_fila('stk-2', producto: 'pro-2', disponible: 12)], w: 'w2');

      expect(await db.select(db.stocks).get(), hasLength(2));
    });

    test('una baja (soft delete) llega como fecha y la fila se conserva', () async {
      await aplicar([_fila('stk-1')]);

      await aplicar([_fila('stk-1', version: 2, baja: '2026-10-28T10:00:00+00:00')], w: 'w2');

      final s = await db.select(db.stocks).getSingle();
      expect(s.deletedAt, DateTime.utc(2026, 10, 28, 10));
    });
  });

  test(
    'un delta con una fila que la tabla rechaza no aplica nada y el watermark no avanza',
    () async {
      await aplicar([_fila('stk-1')]);

      await expectLater(
        aplicar([_fila('stk-2', producto: 'pro-2'), _fila('stk-3', reservada: -5)], w: 'w2'),
        throwsA(anything),
      );

      expect(await db.select(db.stocks).get(), hasLength(1));
      expect(await store.watermarkOf('replica'), 'w1');
    },
  );

  group('la lectura de «Mi stock»', () {
    test('devuelve solo el stock del colportor, ordenado por producto', () async {
      await aplicar([
        _fila('stk-2', producto: 'pro-2', disponible: 4),
        _fila('stk-1', producto: 'pro-1', disponible: 10),
        _fila('stk-9', usuario: 'col-2', producto: 'pro-1', disponible: 99),
      ]);

      final filas = await lectura.observarDe('col-1').first;

      expect(filas.map((f) => (f.productoId, f.cantidadDisponible)), [('pro-1', 10), ('pro-2', 4)]);
    });

    test('sin stock cargado, la lista está vacía (no falla)', () async {
      expect(await lectura.observarDe('col-1').first, isEmpty);
    });

    test('no muestra lo dado de baja', () async {
      await aplicar([
        _fila('stk-1'),
        _fila('stk-2', producto: 'pro-2', baja: '2026-10-28T10:00:00+00:00'),
      ]);

      expect((await lectura.observarDe('col-1').first).map((f) => f.productoId), ['pro-1']);
      expect(await lectura.deProducto('col-1', 'pro-2'), isNull);
    });

    test('se actualiza solo cuando el pull trae un cambio', () async {
      await aplicar([_fila('stk-1', disponible: 10)]);
      final vistos = <int>[];
      final suscripcion = lectura
          .observarDe('col-1')
          .listen((filas) => vistos.add(filas.single.cantidadDisponible));
      addTearDown(suscripcion.cancel);
      await pumpEventQueue();

      await aplicar([_fila('stk-1', disponible: 6, version: 2)], w: 'w2');
      await pumpEventQueue();

      expect(vistos, [10, 6]);
    });
  });
}
