// QA de «Entrega inmediata en el teléfono» (BACK-HU-VEN-002, #430, PR #584). Sin vista: la lógica de
// «Entregar ahora» contra la DB real en memoria, con el motor de sync real (no el encolador falso), el
// cableado de Riverpod y los casos límite que los tests del PR no tocan.
//
// Lo que ya prueba el PR (una venta de 3, combos, idempotencia simple, falla del motor, color de la
// casa) no se repite acá; esto cubre: la cola real y el push al servidor, el reloj y los ids del
// provider, acciones superpuestas (cobrar y entregar a la vez), falla del cálculo de la casa a mitad,
// datos límite, el log sin PII y la casa en edificios y ubicaciones dadas de baja.
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/services/house_status_updater.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/entrega_repository_impl.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/entregar_ahora_use_case.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/registrar_venta_use_case.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/entrega_providers.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

final _ahora = DateTime.utc(2026, 10, 30, 12, 0, 7, 321);

/// Un UUID v7: la versión en el tercer grupo y la variante RFC en el cuarto.
final _uuidV7 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Las columnas de `public.entrega` que puede subir la app (backend 0001; `stock_inconsistente`, 0118,
/// la pone el servidor).
const _columnasDelServidor = {
  'id',
  'venta_id',
  'producto_id',
  'cantidad',
  'fecha_entrega',
  'pendiente',
  'created_at',
  'updated_at',
  'created_by',
  'deleted_at',
  'sync_version',
};

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

/// Un cálculo de la casa que falla las primeras [fallas] veces y después delega en el real.
final class _CasaQueFalla implements HouseStatusUpdater {
  _CasaQueFalla(this._real);

  final HouseStatusUpdater _real;
  int fallas = 1;

  @override
  Future<HouseStatus?> recalcular(
    String ubicacionId, {
    required DateTime ahora,
    required String colportorId,
  }) {
    if (fallas > 0) {
      fallas--;
      throw StateError('el cálculo de la casa se cayó');
    }
    return _real.recalcular(ubicacionId, ahora: ahora, colportorId: colportorId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeConnectivityPort red;
  late SyncEngine motor;
  late MemoryOutput salidaDeLogs;
  late AppLogger logger;
  late HouseStatusUpdaterDrift casas;
  late EntregaLocalDataSourceDrift local;
  late EntregaRepositoryImpl repositorio;
  late VentaLocalDataSourceDrift ventas;
  late CobranzaLocalDataSourceDrift cobranzas;
  var n = 0;
  String generar() => 'e-${++n}';
  var reloj = _ahora;

  EntregarAhoraUseCase casoDeUso([EntregaRepositoryImpl? r]) =>
      EntregarAhoraUseCase(r ?? repositorio, generarId: generar, ahora: () => reloj);

  setUp(() async {
    n = 0;
    reloj = _ahora;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport(pkFieldPorEntidad: const {'house_status': 'ubicacion_id'});
    red = FakeConnectivityPort();
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
      connectivity: red,
    );
    final encolador = EncoladorSyncMotor(motor);
    salidaDeLogs = MemoryOutput();
    logger = AppLogger(
      logger: Logger(level: Level.all, printer: SimplePrinter(), output: salidaDeLogs),
    );
    casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    repositorio = EntregaRepositoryImpl(local, logger: logger);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
  });
  tearDown(() async {
    await motor.dispose();
    await red.dispose();
    await db.close();
  });

  String logs() => salidaDeLogs.buffer.expand((e) => e.lines).join('\n');

  Future<void> vender(String id, List<VentaItem> items, {String vinculo = 'ep-1'}) async {
    final total = items.fold<int>(0, (a, i) => a + i.subtotalCentavos);
    await ventas.registrar(ventaDe(id, monto: total, talonario: 'T-$id', vinculo: vinculo), items);
  }

  Future<void> cobrar(String venta, int monto, {String id = 'c-1'}) => cobranzas.registrar(
    Cobranza(
      id: id,
      ventaId: venta,
      montoCentavos: monto,
      medio: MedioCobranza.efectivo,
      fecha: t0,
      auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
    ),
  );

  Future<List<EntregaFila>> filas() =>
      (db.select(db.entregas)..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
  Future<String?> color([String ub = 'ub-1']) async => (await (db.select(
    db.houseStatuses,
  )..where((h) => h.ubicacionId.equals(ub))).getSingleOrNull())?.color;
  Future<List<SyncQueueFila>> cola() =>
      (db.select(db.syncQueue)..orderBy([(j) => OrderingTerm.asc(j.createdAt)])).get();

  Future<Either<Failure, EntregaRegistrada>> entregar(String venta) =>
      casoDeUso()(EntregarAhoraParams(ventaId: venta, colportorId: 'col-1'));

  group('el cableado real: cola del motor, push al servidor y providers', () {
    test(
      'dado una venta de 3 libros, cuando entrega ahora, la cola real tiene la entrega después de '
      'la venta y sus renglones, con las columnas del servidor',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
        final antes = (await cola()).length;

        final r = await entregar('v-1');

        expect(r.isRight(), isTrue);
        final nuevos = (await cola()).skip(antes).toList();
        expect(
          [for (final j in nuevos) '${j.entity}:${j.op}'],
          ['entrega:insert'], // el color de la casa no cambia: no se vuelve a encolar
        );
        final payload = jsonDecode(nuevos.first.payload) as Map<String, Object?>;
        expect(payload.keys.toSet(), _columnasDelServidor);
        expect(payload['venta_id'], 'v-1');
        expect(payload['producto_id'], 'prod-1');
        expect(payload['cantidad'], 3);
        expect(payload['pendiente'], false);
        expect(payload['created_by'], 'col-1');
        expect(payload['fecha_entrega'], '2026-10-30T12:00:07.321Z');
        // La venta y sus renglones subieron antes (la clave foránea del servidor).
        final entidades = [for (final j in await cola()) j.entity];
        expect(entidades.indexOf('venta'), lessThan(entidades.indexOf('entrega')));
        expect(entidades.indexOf('venta_item'), lessThan(entidades.indexOf('entrega')));
      },
    );

    test(
      'dado la entrega encolada, cuando sincroniza, el servidor recibe la fila entregada y la cola '
      'queda vacía',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
        await entregar('v-1');

        final r = await motor.syncNow();

        expect(r.ok, isTrue, reason: '$r');
        final filasDelServidor = servidor.rowsOf('entrega');
        expect(filasDelServidor, hasLength(1));
        expect(filasDelServidor.single['cantidad'], 3);
        expect(filasDelServidor.single['pendiente'], false);
        expect(filasDelServidor.single['venta_id'], 'v-1');
        expect(
          [for (final j in await cola()) j.state],
          everyElement('DONE'),
          reason: 'todo subió, nada INVALID',
        );
      },
    );

    test(
      'dado el provider real, cuando entrega, usa UUID v7 distintos y la hora de ahora',
      () async {
        final contenedor = ProviderContainer(
          overrides: [
            dbLocalProvider.overrideWith(() => _DbFija(db)),
            transporteSyncProvider.overrideWithValue(servidor),
            relojEntregaProvider.overrideWithValue(() => _ahora),
          ],
        );
        addTearDown(contenedor.dispose);
        await vender('v-1', [
          itemDe('i-1', 'v-1', cantidad: 2),
          itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
        ]);

        final r = await contenedor.read(entregarAhoraUseCaseProvider)(
          const EntregarAhoraParams(ventaId: 'v-1', colportorId: 'col-1'),
        );

        final entregas = r.getOrElse(() => throw StateError('falló')).entregas;
        expect(entregas, hasLength(2));
        for (final e in entregas) {
          expect(e.id, matches(_uuidV7));
          expect(e.fechaEntrega, _ahora);
          expect(e.pendiente, isFalse);
        }
        expect(entregas.map((e) => e.id).toSet(), hasLength(2));
      },
    );

    test(
      'dado el provider sin la DB abierta, cuando se lee, lanza (la pantalla lo traduce a un error)',
      () {
        final contenedor = ProviderContainer(
          overrides: [dbLocalProvider.overrideWith(() => _DbFija(null))],
        );
        addTearDown(contenedor.dispose);

        expect(() => contenedor.read(entregaRepositoryProvider), throwsA(anything));
      },
    );
  });

  group('criterio de la HU: venta de 3 libros + «Entregar ahora»', () {
    test(
      'se crea el registro con todas las cantidades y el material aparece como entregado',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);

        await entregar('v-1');

        final leidas = (await repositorio.deLaVenta('v-1')).getOrElse(() => const []);
        expect(leidas, hasLength(1));
        expect(leidas.single.cantidad, 3);
        expect(leidas.single.pendiente, isFalse);
        expect(leidas.single.fechaEntrega, _ahora);
      },
    );

    test('la hora se guarda en UTC aunque el reloj dé hora local', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 1)]);
      reloj = DateTime(2026, 10, 30, 9, 15, 30);

      await entregar('v-1');

      final f = (await filas()).single;
      expect(f.fechaEntrega!.isUtc, isTrue);
      expect(f.fechaEntrega!.millisecondsSinceEpoch, reloj.millisecondsSinceEpoch);
    });
  });

  group('datos límite', () {
    test(
      'dado 25 productos distintos, cuando entrega ahora, son 25 filas y la casa no se reescribe si no cambia de color',
      () async {
        await vender('v-1', [
          for (var i = 0; i < 25; i++)
            itemDe('i-$i', 'v-1', productoId: 'prod-$i', cantidad: 1 + i, precio: 100),
        ]);
        final antes = (await cola()).length;

        final r = (await entregar('v-1')).getOrElse(() => throw StateError('falló'));

        expect(r.entregas, hasLength(25));
        expect((await filas()).fold<int>(0, (a, f) => a + f.cantidad), 25 * 26 ~/ 2);
        final nuevos = (await cola()).skip(antes).map((j) => j.entity).toList();
        expect(nuevos.where((e) => e == 'entrega'), hasLength(25));
        expect(nuevos.where((e) => e == 'house_status'), isEmpty);
      },
    );

    test(
      'dado el mismo producto en dos renglones sueltos, cuando entrega ahora, es una sola fila',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 2), itemDe('i-2', 'v-1', cantidad: 5)]);

        await entregar('v-1');

        expect([for (final f in await filas()) (f.productoId, f.cantidad)], [('prod-1', 7)]);
      },
    );

    test(
      'dado un combo con el mismo libro dos veces entre los componentes, es una sola fila con la '
      'suma por las unidades',
      () async {
        await vender('v-1', [
          itemDe(
            'i-1',
            'v-1',
            productoId: null,
            coleccionId: 'col-combo',
            componentes: const [
              ComponenteVendido(productoId: 'prod-a'),
              ComponenteVendido(productoId: 'prod-a', cantidad: 2),
            ],
            cantidad: 3,
          ),
        ]);

        await entregar('v-1');

        expect([for (final f in await filas()) (f.productoId, f.cantidad)], [('prod-a', 9)]);
      },
    );

    test(
      'dado que ya se entregó de más un producto, cuando entrega ahora, entrega solo lo que falta '
      'del otro y no compensa',
      () async {
        await vender('v-1', [
          itemDe('i-1', 'v-1', cantidad: 3),
          itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 4),
        ]);
        await db
            .into(db.entregas)
            .insert(
              EntregasCompanion.insert(
                id: 'e-previa',
                ventaId: 'v-1',
                productoId: 'prod-1',
                cantidad: 9,
                createdAt: t0,
                updatedAt: t0,
                pendiente: const Value(false),
                fechaEntrega: Value(t0),
              ),
            );

        final r = (await entregar('v-1')).getOrElse(() => throw StateError('falló'));

        expect(
          [for (final f in await filas()) (f.productoId, f.cantidad)]
            ..sort((a, b) => a.$1.compareTo(b.$1)),
          [('prod-1', 9), ('prod-2', 4)],
        );
        expect(r.yaEstaba, isFalse);
      },
    );

    test('dado ids de solo espacios o de espacio no separable, no guarda nada', () async {
      await vender('v-1', [itemDe('i-1', 'v-1')]);

      for (final malo in ['', '   ', '\t\n', ' ']) {
        final a = await casoDeUso()(EntregarAhoraParams(ventaId: malo, colportorId: 'col-1'));
        final b = await casoDeUso()(EntregarAhoraParams(ventaId: 'v-1', colportorId: malo));
        expect(a.isLeft(), isTrue, reason: 'ventaId «$malo»');
        expect(b.isLeft(), isTrue, reason: 'colportorId «$malo»');
      }
      expect(await filas(), isEmpty);
    });

    test('dado el id de la venta con espacios alrededor, lo recorta y entrega', () async {
      await vender('v-1', [itemDe('i-1', 'v-1')]);

      final r = await casoDeUso()(
        const EntregarAhoraParams(ventaId: '  v-1 ', colportorId: ' col-1 '),
      );

      expect(r.isRight(), isTrue);
      expect((await filas()).single.createdBy, 'col-1');
    });

    test(
      'dado el combo más grande que deja armar la venta, la fila de entrega cabe en el integer del '
      'servidor',
      () async {
        // Una línea admite hasta 99.999 unidades (`maximoPorLinea`) y cada componente hasta 99.999:
        // 99.999 × 99.999 = 9.999.800.001, que no entra en `integer` (2.147.483.647) de `entrega.cantidad`.
        const unidades = RegistrarVentaUseCase.maximoPorLinea;
        await vender('v-1', [
          itemDe(
            'i-1',
            'v-1',
            productoId: null,
            coleccionId: 'col-combo',
            componentes: const [
              ComponenteVendido(
                productoId: 'prod-a',
                cantidad: RegistrarVentaUseCase.maximoPorLinea,
              ),
            ],
            cantidad: unidades,
            precio: 1,
          ),
        ]);

        await entregar('v-1');

        for (final f in await filas()) {
          expect(f.cantidad, lessThanOrEqualTo(2147483647));
        }
      },
      skip:
          'QA #430: combo × componente al máximo da una cantidad de entrega mayor que el integer '
          'del servidor (el push de esa fila se rechazaría para siempre)',
    );
  });

  group('acciones superpuestas', () {
    test(
      'dado cinco toques a la vez, cuando entrega ahora, una sola escribe y las otras cuatro dicen '
      'que ya estaba',
      () async {
        await vender('v-1', [
          itemDe('i-1', 'v-1', cantidad: 3),
          itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
        ]);
        final antes = (await cola()).length;

        final rs = await Future.wait([for (var i = 0; i < 5; i++) entregar('v-1')]);

        final reg = [for (final r in rs) r.getOrElse(() => throw StateError('falló'))];
        expect(reg.where((r) => !r.yaEstaba), hasLength(1));
        expect(reg.where((r) => r.yaEstaba), hasLength(4));
        expect(await filas(), hasLength(2));
        expect((await cola()).skip(antes).where((j) => j.entity == 'entrega'), hasLength(2));
        // Las cinco respuestas muestran las mismas filas.
        expect(reg.map((r) => r.entregas.length).toSet(), {2});
      },
    );

    for (final entregaPrimero in [true, false]) {
      test(
        'dado cobrar lo último y entregar a la vez (${entregaPrimero ? 'entrega' : 'cobro'} primero), '
        'la casa termina en «Venta completa»',
        () async {
          await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
          await cobrar('v-1', 100000);

          final futuros = entregaPrimero
              ? [entregar('v-1'), cobrar('v-1', 50000, id: 'c-2')]
              : [cobrar('v-1', 50000, id: 'c-2'), entregar('v-1')];
          await Future.wait<Object?>(futuros);

          expect(await color(), 'VENTA_COMPLETA');
          expect(await filas(), hasLength(1));
        },
      );
    }

    test('dado dos ventas de la misma casa pagadas, cuando se entregan a la vez, cada una tiene su '
        'fila y la casa queda «Venta completa»', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 1)]);
      await vender('v-2', [itemDe('i-2', 'v-2', productoId: 'prod-2', cantidad: 2)]);
      await cobrar('v-1', 50000);
      await cobrar('v-2', 100000, id: 'c-2');

      await Future.wait([entregar('v-1'), entregar('v-2')]);

      expect([
        for (final f in await filas()) (f.ventaId, f.productoId, f.cantidad),
      ], unorderedEquals([('v-1', 'prod-1', 1), ('v-2', 'prod-2', 2)]));
      expect(await color(), 'VENTA_COMPLETA');
    });
  });

  group('falla a mitad de la acción', () {
    test('dado que el cálculo de la casa falla, cuando entrega ahora, no queda fila ni job y el '
        'reintento entrega todo', () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 3),
        itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
      ]);
      final antes = (await cola()).length;
      final colorAntes = await color();
      final fallona = _CasaQueFalla(casas);
      final repo = EntregaRepositoryImpl(
        EntregaLocalDataSourceDrift(
          db,
          encolador: EncoladorSyncMotor(motor),
          estadoDeLasCasas: fallona,
        ),
        logger: logger,
      );

      final primera = await casoDeUso(repo)(
        const EntregarAhoraParams(ventaId: 'v-1', colportorId: 'col-1'),
      );

      expect(primera.isLeft(), isTrue);
      expect(await filas(), isEmpty);
      expect((await cola()).length, antes, reason: 'ningún job quedó a medias');
      expect(await color(), colorAntes);

      final segunda = await casoDeUso(repo)(
        const EntregarAhoraParams(ventaId: 'v-1', colportorId: 'col-1'),
      );

      final r = segunda.getOrElse(() => throw StateError('falló'));
      expect(r.yaEstaba, isFalse);
      expect(r.entregas, hasLength(2));
      expect(await filas(), hasLength(2));
    });

    test(
      'dado que falla, el aviso dice qué pasó y qué hacer, sin la venta ni la excepción',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1')]);
        final repo = EntregaRepositoryImpl(
          EntregaLocalDataSourceDrift(
            db,
            encolador: EncoladorSyncEnMemoria(fallarCon: StateError('contraseña=hunter2')),
            estadoDeLasCasas: casas,
          ),
          logger: logger,
        );

        final r = await casoDeUso(repo)(
          const EntregarAhoraParams(ventaId: 'v-1', colportorId: 'col-1'),
        );

        final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
        expect(falla, isA<FailureEntregaNoGuardada>());
        expect(falla.mensaje, contains('No se registró nada'));
        expect(falla.mensaje, contains('probá de nuevo'));
        expect('${falla.mensaje} ${falla.codigo}', isNot(contains('v-1')));
        expect(logs(), isNot(contains('hunter2')));
        expect(logs(), contains('ENTREGA_ALTA_FAIL'));
      },
    );

    test(
      'dado una venta que no existe, el aviso es el mismo de «no pudimos guardar» y el log no lleva '
      'la excepción',
      () async {
        final r = await entregar('v-fantasma');

        final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
        expect(falla, isA<FailureEntregaNoGuardada>());
        expect(logs(), contains('ENTREGA_ALTA_RECHAZADA'));
      },
    );

    test(
      'dado que la lectura falla (tabla ausente), devuelve «no disponible» y no «nada entregado»',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1')]);
        await db.customStatement('DROP TABLE entrega');

        final r = await repositorio.deLaVenta('v-1');

        expect(
          r.swap().getOrElse(() => throw StateError('debía fallar')),
          isA<FailureEntregaNoDisponible>(),
        );
      },
    );
  });

  group('el color de la casa en los bordes', () {
    test('dado un edificio, cuando se paga y entrega un depto pero el otro debe, la casa sigue '
        'pendiente; al pagar y entregar el otro, queda «Venta completa»', () async {
      await db.close();
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      final encolador = EncoladorSyncEnMemoria();
      final casasE = HouseStatusUpdaterDrift(db, encolador: encolador);
      final localE = EntregaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: casasE,
      );
      final ventasE = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casasE);
      final cobrosE = CobranzaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: casasE,
      );
      await sembrarEdificio(db);
      await ventasE.registrar(ventaDe('v-1', monto: 150000, talonario: 'T1', vinculo: 'ep-1'), [
        itemDe('i-1', 'v-1', cantidad: 3),
      ]);
      await ventasE.registrar(ventaDe('v-2', monto: 100000, talonario: 'T2', vinculo: 'ep-2'), [
        itemDe('i-2', 'v-2', productoId: 'prod-2', cantidad: 2),
      ]);
      Cobranza cobro(String id, String venta, int monto) => Cobranza(
        id: id,
        ventaId: venta,
        montoCentavos: monto,
        medio: MedioCobranza.efectivo,
        fecha: t0,
        auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
      );
      await cobrosE.registrar(cobro('c-1', 'v-1', 150000));

      await localE.entregarAhora('v-1', colportorId: 'col-1', ahora: _ahora, generarId: generar);
      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

      await cobrosE.registrar(cobro('c-2', 'v-2', 100000));
      await localE.entregarAhora('v-2', colportorId: 'col-1', ahora: _ahora, generarId: generar);
      expect(await color(), 'VENTA_COMPLETA');
    });

    test('dado una entrega parcial, cuando se paga todo, la casa sigue pendiente hasta entregar lo '
        'que falta', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 5)]);
      await cobrar('v-1', 250000);
      await db
          .into(db.entregas)
          .insert(
            EntregasCompanion.insert(
              id: 'e-previa',
              ventaId: 'v-1',
              productoId: 'prod-1',
              cantidad: 3,
              createdAt: t0,
              updatedAt: t0,
              pendiente: const Value(false),
              fechaEntrega: Value(t0),
            ),
          );
      await casas.recalcular('ub-1', ahora: t0, colportorId: 'col-1');
      expect(await color(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

      await entregar('v-1');

      expect((await filas()).fold<int>(0, (a, f) => a + f.cantidad), 5);
      expect(await color(), 'VENTA_COMPLETA');
    });

    test(
      'dado una ubicación dada de baja, cuando entrega ahora, la entrega se guarda y no se pinta '
      'la casa',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1')]);
        await (db.update(db.ubicaciones)).write(UbicacionesCompanion(deletedAt: Value(t0)));

        final r = await entregar('v-1');

        expect(r.isRight(), isTrue);
        expect(await filas(), hasLength(1));
      },
    );

    test('dado una venta de \$ 0 entregada, la casa no pasa a «Venta completa»', () async {
      await ventas.registrar(ventaDe('v-0', monto: 0, talonario: 'T0'), [
        itemDe('i-0', 'v-0', cantidad: 1, precio: 0),
      ]);

      await entregar('v-0');

      expect(await color(), isNot('VENTA_COMPLETA'));
    });
  });

  group('privacidad', () {
    test(
      'dado un error de la base con la sentencia SQL, el log y la falla llevan solo el tipo',
      () async {
        await vender('v-1', [
          itemDe('i-1', 'v-1', cantidad: 3),
          itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
        ]);
        final r = await EntregarAhoraUseCase(
          repositorio,
          generarId: () => 'igual',
          ahora: () => _ahora,
        )(const EntregarAhoraParams(ventaId: 'v-1', colportorId: 'col-1'));

        final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
        expect(falla, isA<FailureEntregaNoGuardada>());
        final texto =
            '${falla.mensaje} ${falla.codigo} ${(falla as FailureEntregaNoGuardada).causa}';
        for (final fuga in ['INSERT', 'UNIQUE', 'igual', 'prod-1', 'v-1']) {
          expect(texto, isNot(contains(fuga)));
          expect(logs(), isNot(contains(fuga == 'v-1' ? 'zzz' : fuga)));
        }
        expect(logs(), contains('ENTREGA_ALTA_FAIL'));
      },
    );
  });
}
