// «Reintentar» y la unión de duplicados que el teléfono ya deshizo (HU-UBI-006; decisión del 10/11,
// #688 P1): el trabajo «marcar como duplicado» rechazado y deshecho sigue a la vista, pero no vuelve a
// la cola, porque el servidor uniría lo que el teléfono separó.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/uniones_locales_table.dart';
import 'package:colportores_mobile/features/sincronizacion/data/repositories/uniones_deshechas_repository_impl.dart';
import 'package:colportores_mobile/features/sincronizacion/data/services/servicio_sincronizacion_motor.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/repositories/uniones_deshechas_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

import '../../../helpers/logger_mudo.dart';

class _Deshechas implements UnionesDeshechasRepository {
  _Deshechas(this.ids);

  Set<String> ids;

  @override
  Future<Set<String>> trabajos() async => ids;
}

typedef _Banco = ({SyncEngine motor, _Deshechas uniones, ServicioSincronizacionMotor servicio});

void main() {
  /// Una unión y dos ventas rechazadas por el servidor: tres trabajos `INVALID`.
  Future<_Banco> armar() async {
    final transport = FakeSyncTransport()
      ..seed('ubicacion', [
        {'id': 'ub-a'},
        {'id': 'ub-b'},
      ])
      ..rejectJob('op-union', 'UB003')
      ..rejectJob('op-v1', '23514')
      ..rejectJob('op-v2', '23514');
    final motor = SyncEngine(
      specs: SpecRegistry(
        [SyncSpec.push('ubicacion'), SyncSpec.push('venta')],
        allEntities: {'ubicacion', 'venta'},
      ),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: InMemoryLocalStore(),
      connectivity: FakeConnectivityPort(),
    );
    addTearDown(motor.dispose);
    await motor.stage('ubicacion', Op.marcarComoDuplicado, const {
      'duplicada_id': 'ub-b',
      'conservada_id': 'ub-a',
    }, clientOpId: 'op-union');
    await motor.stage('venta', Op.insert, const {'id': 'v-1'}, clientOpId: 'op-v1');
    await motor.stage('venta', Op.insert, const {'id': 'v-2'}, clientOpId: 'op-v2');
    await motor.syncNow();
    final uniones = _Deshechas({});
    final servicio = ServicioSincronizacionMotor(motor, uniones);
    final union = (await servicio.operacionesFallidas()).firstWhere((o) => o.tabla == 'ubicacion');
    uniones.ids = {union.id};
    return (motor: motor, uniones: uniones, servicio: servicio);
  }

  group('«Reintentar las N»', () {
    test('dado una unión deshecha y dos ventas rechazadas, cuando reintento todas, vuelven las dos '
        'ventas, la cuenta es 2 y la unión sigue rechazada', () async {
      final b = await armar();

      final n = await b.servicio.reintentarFallidas();

      final estado = await b.motor.statusNow();
      expect(n, 2);
      expect(estado.pending, 2);
      expect(estado.invalid, 1);
      expect((await b.servicio.operacionesFallidas()).single.tabla, 'ubicacion');
    });

    test(
      'dado solo la unión deshecha rechazada, cuando reintento todas, no vuelve nada y la cuenta '
      'es 0',
      () async {
        final b = await armar();
        // Se sacan las ventas de la cola de error para dejar solo la unión.
        final ventas = [
          for (final o in await b.servicio.operacionesFallidas())
            if (o.tabla == 'venta') o.id,
        ];
        await b.motor.discard(ventas);

        final n = await b.servicio.reintentarFallidas();

        expect(n, 0);
        expect((await b.motor.statusNow()).pending, 0);
        expect((await b.motor.statusNow()).invalid, 1);
      },
    );

    test('dado una unión rechazada que el teléfono todavía no deshizo, cuando reintento todas, '
        'vuelve a la cola como cualquier otra', () async {
      final b = await armar();
      b.uniones.ids = {};

      final n = await b.servicio.reintentarFallidas();

      expect(n, 3);
      expect((await b.motor.statusNow()).pending, 3);
    });

    test('dado nada rechazado, cuando reintento todas, la cuenta es 0', () async {
      final b = await armar();
      await b.motor.discard([for (final o in await b.servicio.operacionesFallidas()) o.id]);

      expect(await b.servicio.reintentarFallidas(), 0);
    });
  });

  group('«Reintentar» de una operación', () {
    test('dado la unión deshecha, no vuelve a la cola, devuelve 0 y sigue a la vista', () async {
      final b = await armar();
      final union = (await b.servicio.operacionesFallidas()).firstWhere(
        (o) => o.tabla == 'ubicacion',
      );

      final n = await b.servicio.reintentarFallidas(id: union.id);

      expect(n, 0);
      expect((await b.motor.statusNow()).pending, 0);
      expect((await b.servicio.operacionesFallidas()).map((o) => o.id), contains(union.id));
    });

    test(
      'dado una venta rechazada con la unión deshecha al lado, vuelve a la cola y devuelve 1',
      () async {
        final b = await armar();
        final venta = (await b.servicio.operacionesFallidas()).firstWhere(
          (o) => o.tabla == 'venta',
        );

        final n = await b.servicio.reintentarFallidas(id: venta.id);

        expect(n, 1);
        expect((await b.motor.statusNow()).pending, 1);
      },
    );
  });

  group('UnionesDeshechasRepositoryImpl (DB local real)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo()));
    tearDown(() => db.close());

    Future<void> union(String trabajoId, String estado) => db
        .into(db.unionesLocales)
        .insert(
          UnionesLocalesCompanion.insert(
            trabajoId: trabajoId,
            conservadaId: 'ub-a',
            duplicadaId: 'ub-$trabajoId',
            unidaEn: DateTime.utc(2026, 11, 2),
            movimientos: '{}',
            estado: Value(estado),
          ),
        );

    test(
      'dado uniones aplicadas y deshechas, devuelve solo los trabajos de las deshechas',
      () async {
        await union('t-1', EstadoUnionLocal.aplicada);
        await union('t-2', EstadoUnionLocal.deshecha);
        await union('t-3', EstadoUnionLocal.deshecha);

        expect(await UnionesDeshechasRepositoryImpl(db).trabajos(), {'t-2', 't-3'});
      },
    );

    test('dado ninguna unión, devuelve vacío', () async {
      expect(await UnionesDeshechasRepositoryImpl(db).trabajos(), isEmpty);
    });
  });
}
