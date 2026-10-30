// «Entregar ahora» contra las tablas reales (HU-VEN-002, #430): AppDatabase en memoria, mismo esquema
// y mismos CHECK que en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/models/entrega_model.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

final _ahora = DateTime.utc(2026, 10, 29, 15, 30, 5, 250);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late EntregaLocalDataSourceDrift local;
  late VentaLocalDataSourceDrift ventas;
  late CobranzaLocalDataSourceDrift cobranzas;
  var n = 0;
  String generar() => 'e-${++n}';

  setUp(() async {
    n = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  /// Una venta de `ep-1` con los [items] dados (su monto es la suma de los subtotales).
  Future<void> vender(String id, List<VentaItem> items, {String talonario = 'T-1'}) async {
    final total = items.fold<int>(0, (a, i) => a + i.subtotalCentavos);
    await ventas.registrar(ventaDe(id, monto: total, talonario: talonario), items);
    encolador.encolados.clear();
  }

  Future<EntregaRegistrada> entregar(String venta) =>
      local.entregarAhora(venta, colportorId: 'col-1', ahora: _ahora, generarId: generar);

  Future<void> cobrarTodo(String venta, int monto, {String id = 'c-1'}) async {
    await cobranzas.registrar(
      Cobranza(
        id: id,
        ventaId: venta,
        montoCentavos: monto,
        medio: MedioCobranza.efectivo,
        fecha: t0,
        auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
      ),
    );
  }

  Future<List<EntregaFila>> filas() =>
      (db.select(db.entregas)..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
  Future<String?> colorDeLaCasa() async =>
      (await db.select(db.houseStatuses).getSingleOrNull())?.color;
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  group('entregar ahora', () {
    test('dado una venta de 3 libros, cuando entrega ahora, crea una fila de 3 ya entregada con la '
        'fecha de ahora', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);

      final r = await entregar('v-1');

      final fila = (await filas()).single;
      expect(fila.id, 'e-1');
      expect(fila.ventaId, 'v-1');
      expect(fila.productoId, 'prod-1');
      expect(fila.cantidad, 3);
      expect(fila.pendiente, isFalse);
      expect(fila.fechaEntrega, _ahora);
      expect(fila.createdBy, 'col-1');
      expect(r.entregas.single.cantidad, 3);
      expect(r.yaEstaba, isFalse);
      expect(r.quedaPendiente, isFalse);
    });

    test('dado dos productos, cuando entrega ahora, crea una fila por producto con todas las '
        'cantidades', () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 2),
        itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 5, precio: 1000),
      ]);

      await entregar('v-1');

      expect(
        [for (final f in await filas()) (f.productoId, f.cantidad)],
        [('prod-1', 2), ('prod-2', 5)],
      );
    });

    test(
      'dado un combo, cuando entrega ahora, crea una fila por componente con su cantidad por las '
      'unidades vendidas',
      () async {
        await vender('v-1', [
          itemDe(
            'i-1',
            'v-1',
            productoId: null,
            coleccionId: 'col-combo',
            componentes: const [
              ComponenteVendido(productoId: 'prod-a'),
              ComponenteVendido(productoId: 'prod-b', cantidad: 2),
            ],
            cantidad: 2,
            precio: 90000,
          ),
        ]);

        await entregar('v-1');

        expect(
          [for (final f in await filas()) (f.productoId, f.cantidad)],
          [('prod-a', 2), ('prod-b', 4)],
        );
      },
    );

    test(
      'dado el mismo producto suelto y dentro de un combo, cuando entrega ahora, es una sola fila '
      'con la suma',
      () async {
        await vender('v-1', [
          itemDe('i-1', 'v-1', cantidad: 1),
          itemDe(
            'i-2',
            'v-1',
            productoId: null,
            coleccionId: 'col-combo',
            componentes: const [ComponenteVendido(productoId: 'prod-1')],
            cantidad: 2,
            precio: 40000,
          ),
        ]);

        await entregar('v-1');

        expect([for (final f in await filas()) (f.productoId, f.cantidad)], [('prod-1', 3)]);
      },
    );

    test('dado un renglón dado de baja, cuando entrega ahora, no lo entrega', () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 2),
        itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
      ]);
      await (db.update(
        db.ventaItems,
      )..where((i) => i.id.equals('i-2'))).write(VentaItemsCompanion(deletedAt: Value(t0)));

      await entregar('v-1');

      expect([for (final f in await filas()) f.productoId], ['prod-1']);
    });

    test('dado que sube, cuando entrega ahora, encola cada fila como entrega:insert sin dato del '
        'cliente', () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 2),
        itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
      ]);

      await entregar('v-1');

      // La casa ya estaba en «pendiente» y sigue igual: no se encola nada más que las filas.
      expect(cola(), ['entrega:insert', 'entrega:insert']);
      final payload = encolador.encolados.first.payload;
      expect(payload.keys.toSet(), {
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
      });
      expect(payload['venta_id'], 'v-1');
      expect(payload['pendiente'], false);
      expect(payload['fecha_entrega'], _ahora.toIso8601String());
      expect(payload.containsKey('stock_inconsistente'), isFalse);
    });
  });

  group('idempotencia', () {
    test('dado una venta ya entregada, cuando vuelve a entregar, no escribe ni encola nada y dice '
        'que ya estaba', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
      await entregar('v-1');
      encolador.encolados.clear();

      final otra = await entregar('v-1');

      expect(otra.yaEstaba, isTrue);
      expect(otra.entregas.single.id, 'e-1');
      expect(await filas(), hasLength(1));
      expect(encolador.encolados, isEmpty);
    });

    test('dado un doble toque, cuando dos entregas llegan juntas, una sola escribe', () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 3),
        itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
      ]);

      final r = await Future.wait([entregar('v-1'), entregar('v-1')]);

      expect(await filas(), hasLength(2));
      expect(r.where((e) => e.yaEstaba), hasLength(1));
      expect(cola().where((c) => c == 'entrega:insert'), hasLength(2));
    });

    test('dado una entrega parcial previa, cuando entrega ahora, crea solo lo que falta', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
      await db
          .into(db.entregas)
          .insert(
            EntregasCompanion.insert(
              id: 'previa',
              ventaId: 'v-1',
              productoId: 'prod-1',
              cantidad: 1,
              pendiente: const Value(false),
              fechaEntrega: Value(t0),
              createdAt: t0,
              updatedAt: t0,
            ),
          );

      await entregar('v-1');

      expect([for (final f in await filas()) (f.id, f.cantidad)], [('e-1', 2), ('previa', 1)]);
    });

    test(
      'dado una fila de entrega dada de baja, cuando entrega ahora, no la cuenta como entregada',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
        await entregar('v-1');
        await (db.update(db.entregas)).write(EntregasCompanion(deletedAt: Value(t0)));
        n = 10;

        final r = await entregar('v-1');

        expect(r.yaEstaba, isFalse);
        expect(r.entregas.single.id, 'e-11');
      },
    );

    test('dado una venta sin renglones vivos, cuando entrega ahora, no hay nada que entregar y no '
        'escribe', () async {
      await vender('v-1', [itemDe('i-1', 'v-1')]);
      await (db.update(db.ventaItems)).write(VentaItemsCompanion(deletedAt: Value(t0)));

      final r = await entregar('v-1');

      expect(r.yaEstaba, isTrue);
      expect(r.entregas, isEmpty);
      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });
  });

  group('fallas', () {
    test('dado una venta que no está, cuando entrega ahora, lanza EntregaSinVentaException y no '
        'escribe', () async {
      await expectLater(entregar('v-x'), throwsA(isA<EntregaSinVentaException>()));

      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test(
      'dado una venta dada de baja, cuando entrega ahora, lanza EntregaSinVentaException',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1')]);
        await (db.update(db.ventas)).write(VentasCompanion(deletedAt: Value(t0)));

        await expectLater(entregar('v-1'), throwsA(isA<EntregaSinVentaException>()));
        expect(await filas(), isEmpty);
      },
    );

    test(
      'dado que el motor falla con la segunda fila, cuando entrega ahora, no queda ninguna fila y '
      'el reintento entrega todo',
      () async {
        await vender('v-1', [
          itemDe('i-1', 'v-1', cantidad: 3),
          itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
        ]);
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = 1;

        await expectLater(entregar('v-1'), throwsA(isA<StateError>()));
        expect(await filas(), isEmpty);
        expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

        encolador.fallarCon = null;
        final r = await entregar('v-1');

        expect(r.yaEstaba, isFalse);
        expect(await filas(), hasLength(2));
      },
    );

    test('dado un id repetido, cuando entrega ahora, no queda a medias', () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 3),
        itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
      ]);

      await expectLater(
        local.entregarAhora('v-1', colportorId: 'col-1', ahora: _ahora, generarId: () => 'igual'),
        throwsA(anything),
      );

      expect(await filas(), isEmpty);
    });
  });

  group('el color de la casa', () {
    test(
      'dado una venta pagada, cuando entrega ahora, la casa queda «Venta completa» (4)',
      () async {
        await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
        await cobrarTodo('v-1', 150000);
        expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

        final r = await entregar('v-1');

        expect(await colorDeLaCasa(), 'VENTA_COMPLETA');
        expect(r.colorDeLaCasa?.codigo, 'VENTA_COMPLETA');
        expect(cola().last, 'house_status:update');
      },
    );

    test('dado una venta entregada, cuando se cobra lo último que debe, la casa queda «Venta '
        'completa» (4)', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
      await entregar('v-1');
      await cobrarTodo('v-1', 100000);
      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

      await cobrarTodo('v-1', 50000, id: 'c-2');

      expect(await colorDeLaCasa(), 'VENTA_COMPLETA');
    });

    test('dado una venta con saldo, cuando entrega ahora, la casa sigue pendiente (1)', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
      await cobrarTodo('v-1', 50000);

      final r = await entregar('v-1');

      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      expect(r.colorDeLaCasa?.codigo, 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test('dado una venta pagada pero sin entregar, la casa sigue pendiente (1)', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);

      await cobrarTodo('v-1', 150000);

      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test('dado otra venta de la casa sin entregar, cuando se entrega y paga una, la casa sigue '
        'pendiente (1)', () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 3)]);
      await vender('v-2', [itemDe('i-2', 'v-2', cantidad: 1)], talonario: 'T-2');
      await cobrarTodo('v-1', 150000);

      await entregar('v-1');

      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

      await entregar('v-2');
      await cobrarTodo('v-2', 50000, id: 'c-2');

      expect(await colorDeLaCasa(), 'VENTA_COMPLETA');
    });

    test(
      'dado una venta cuya casa no está en el teléfono, cuando entrega ahora, se guarda igual sin '
      'color',
      () async {
        await sembrarVinculo(db, id: 'ep-9', espacioId: 'esp-9', personaId: 'per-9');
        await ventas.registrar(ventaDe('v-9', vinculo: 'ep-9', talonario: 'T-9'), [
          itemDe('i-9', 'v-9'),
        ]);

        final r = await entregar('v-9');

        expect(r.colorDeLaCasa, isNull);
        expect(await filas(), hasLength(1));
      },
    );
  });

  group('lectura', () {
    test('dado una venta sin entregas, cuando se lee, es una lista vacía', () async {
      await vender('v-1', [itemDe('i-1', 'v-1')]);

      expect(await local.deLaVenta('v-1'), isEmpty);
    });

    test('dado filas vivas y dadas de baja, cuando se lee, trae solo las vivas', () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 3),
        itemDe('i-2', 'v-1', productoId: 'prod-2', cantidad: 1),
      ]);
      await entregar('v-1');
      await (db.update(
        db.entregas,
      )..where((e) => e.id.equals('e-1'))).write(EntregasCompanion(deletedAt: Value(t0)));

      expect([for (final e in await local.deLaVenta('v-1')) e.id], ['e-2']);
    });
  });

  group('el modelo y el sync', () {
    test('dado una entrega pendiente, cuando se arma el JSON, la fecha va vacía', () {
      final json = EntregaModel.toJson(
        Entrega(
          id: 'e-1',
          ventaId: 'v-1',
          productoId: 'prod-1',
          cantidad: 2,
          pendiente: true,
          auditoria: auditoriaDe(),
        ),
      );

      expect(json['pendiente'], true);
      expect(json['fecha_entrega'], isNull);
      expect(json['cantidad'], 2);
    });

    test(
      '`entrega` sube como las ventas: sin escritura crítica, sin pull y después de los ítems',
      () {
        final entidades = [for (final s in specsDeLaApp) s.entity];

        expect(entidades, containsAllInOrder(['venta', 'venta_item', 'entrega']));
        final spec = specsDeLaApp.firstWhere((s) => s.entity == 'entrega');
        expect(spec.critical, isFalse);
        expect(spec.alsoPull, isFalse);
        expect(spec.pullable, isFalse);
        expect(spec.pk, 'id');
      },
    );

    test('el CHECK de la tabla rechaza una cantidad de cero', () async {
      await expectLater(
        db
            .into(db.entregas)
            .insert(
              EntregasCompanion.insert(
                id: 'e-0',
                ventaId: 'v-1',
                productoId: 'prod-1',
                cantidad: 0,
                createdAt: t0,
                updatedAt: t0,
              ),
            ),
        throwsA(anything),
      );
    });
  });
}
