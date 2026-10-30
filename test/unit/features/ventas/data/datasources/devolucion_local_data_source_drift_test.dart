// Registrar una devolución contra las tablas reales (HU-VEN-004, #161): AppDatabase en memoria, mismo
// esquema y mismos CHECK que en el dispositivo, con el servicio real de `house_status`. Los números son
// los del canvas 31: una venta de $ 4.500 con «Salud y Hogar» ($ 2.600) y «Nuestros Hijos» ($ 1.900).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/devolucion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/estado_de_entrega.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

/// El momento de la venta y 24 h después: el de las devoluciones, salvo que el test diga otro.
final _venta = t0;
final _ahora = t0.add(const Duration(hours: 24));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late DevolucionLocalDataSourceDrift local;
  late VentaLocalDataSourceDrift ventas;
  late CobranzaLocalDataSourceDrift cobranzas;
  late EntregaLocalDataSourceDrift entregas;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = DevolucionLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    cobranzas = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    entregas = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Future<void> cobrar(int monto, {String id = 'c-1'}) async {
    await cobranzas.registrar(
      Cobranza(
        id: id,
        ventaId: 'v-1',
        montoCentavos: monto,
        medio: MedioCobranza.efectivo,
        fecha: _venta,
        auditoria: Auditoria(createdAt: _ahora, updatedAt: _ahora, createdBy: 'col-1'),
      ),
    );
  }

  /// La venta del canvas: dos renglones de un libro, $ 4.500, con lo [cobrado] ya cobrado.
  Future<void> venderElCanvas({int cobrado = 450000, DateTime? fecha}) async {
    await ventas.registrar(ventaDe('v-1', monto: 450000, fecha: fecha ?? _venta), [
      itemDe('i-salud', 'v-1', productoId: 'p-salud', cantidad: 1, precio: 260000),
      itemDe('i-hijos', 'v-1', productoId: 'p-hijos', cantidad: 1, precio: 190000),
    ]);
    if (cobrado > 0) await cobrar(cobrado);
    encolador.encolados.clear();
  }

  PedidoDeDevolucion pedido(
    Map<String, int> unidades, {
    String id = 'd-1',
    QueHacerConLaDiferencia? queHacer,
    String? motivo,
    DateTime? ahora,
    String ventaId = 'v-1',
  }) => PedidoDeDevolucion(
    id: id,
    ventaId: ventaId,
    colportorId: 'col-1',
    unidadesPorRenglon: unidades,
    queHacer: queHacer,
    motivo: motivo,
    ahora: ahora ?? _ahora,
  );

  Future<List<DevolucionFila>> filas() =>
      (db.select(db.devoluciones)..orderBy([(d) => OrderingTerm.asc(d.id)])).get();
  Future<String?> colorDeLaCasa() async =>
      (await db.select(db.houseStatuses).getSingleOrNull())?.color;
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<int> saldoDeLaVenta() async => (await cobranzas.ventaConSaldo('v-1'))!.saldoCentavos;

  group('registrar', () {
    test('31-03: dado que pagó de más y elige «Se lo devuelvo ahora», guarda lo devuelto como '
        'reembolsado y encola la devolución', () async {
      await venderElCanvas();

      final r = await local.registrar(
        pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.devolverAhora),
      );

      final fila = (await filas()).single;
      expect(fila.ventaId, 'v-1');
      expect(fila.productosDevueltos, [
        {'producto_id': 'p-hijos', 'cantidad': 1, 'venta_item_id': 'i-hijos'},
      ]);
      expect(fila.montoReembolsado, 190000);
      expect(fila.dineroRetenido, 0);
      expect(fila.fechaDevolucion, _ahora);
      expect(fila.createdBy, 'col-1');
      expect(r.totalCentavos, 260000);
      expect(r.saldoCentavos, 0);
      expect(r.deboAlClienteCentavos, 0);
      expect(r.eraTotal, isFalse);
      expect(r.yaEstaba, isFalse);
      expect(cola().first, 'devolucion:insert');
    });

    test(
      'dado «Lo retengo», guarda la diferencia como dinero retenido y el saldo queda en cero',
      () async {
        await venderElCanvas();

        final r = await local.registrar(
          pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.retener),
        );

        final fila = (await filas()).single;
        expect(fila.dineroRetenido, 190000);
        expect(fila.montoReembolsado, isNull);
        expect(r.saldoCentavos, 0);
        expect(r.deboAlClienteCentavos, 0);
      },
    );

    test(
      '31-04: dado «Se lo devuelvo después», no guarda monto y queda «Debo al cliente»',
      () async {
        await venderElCanvas();

        final r = await local.registrar(
          pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.devolverDespues),
        );

        final fila = (await filas()).single;
        expect(fila.dineroRetenido, 0);
        expect(fila.montoReembolsado, isNull);
        expect(r.deboAlClienteCentavos, 190000);
        expect(r.totalCentavos, 260000);
      },
    );

    test(
      '31-06: dado que debía más, la devolución solo ajusta el saldo y no pide elegir',
      () async {
        await venderElCanvas(cobrado: 100000);

        final r = await local.registrar(pedido({'i-hijos': 1}));

        expect(r.saldoCentavos, 160000);
        expect(r.deboAlClienteCentavos, 0);
        expect((await filas()).single.montoReembolsado, isNull);
        expect(await saldoDeLaVenta(), 160000);
      },
    );

    test('dado el motivo, lo guarda limpio y sube con la devolución', () async {
      await venderElCanvas(cobrado: 0);

      await local.registrar(pedido({'i-hijos': 1}, motivo: 'no le gustó'));

      expect((await filas()).single.motivo, 'no le gustó');
      expect(encolador.encolados.first.payload['motivo'], 'no le gustó');
    });

    test(
      'dado el push, sube con las claves del contrato y sin dato del cliente ni colportor_id',
      () async {
        await venderElCanvas();

        await local.registrar(
          pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.devolverAhora, motivo: 'x'),
        );

        final payload = encolador.encolados.first.payload;
        expect(payload.keys.toSet(), {
          'id',
          'venta_id',
          'productos_devueltos',
          'dinero_retenido',
          'monto_reembolsado',
          'motivo',
          'fecha_devolucion',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        });
        expect(payload['productos_devueltos'], [
          {'producto_id': 'p-hijos', 'cantidad': 1, 'venta_item_id': 'i-hijos'},
        ]);
        expect(payload['monto_reembolsado'], 190000);
        expect(payload['fecha_devolucion'], _ahora.toIso8601String());
        expect(payload.containsKey('colportor_id'), isFalse);
      },
    );

    test(
      'dado que la devolución cambia el color de la casa, el push va antes que el de la casa',
      () async {
        await venderElCanvas();
        await entregas.entregarAhora(
          'v-1',
          colportorId: 'col-1',
          ahora: _ahora,
          generarId: () => 'e-${encolador.encolados.length}',
        );
        encolador.encolados.clear();

        await local.registrar(
          pedido({'i-salud': 1, 'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.retener),
        );

        expect(cola().first, 'devolucion:insert');
        expect(cola().skip(1).every((c) => c.startsWith('house_status')), isTrue);
      },
    );
  });

  group('audit_log_local (HU-VEN-004)', () {
    Future<List<AuditLogFila>> auditoria() =>
        (db.select(db.auditLogLocal)..orderBy([(a) => OrderingTerm.asc(a.id)])).get();

    test(
      'dado el motivo, deja una fila con el id de la devolución, el motivo y la fecha',
      () async {
        await venderElCanvas(cobrado: 0);

        await local.registrar(pedido({'i-hijos': 1}, motivo: 'no le gustó'));

        final fila = (await auditoria()).single;
        expect(fila.evento, EventoAuditoriaLocal.devolucionRegistrada);
        expect(fila.uuid, 'd-1');
        expect(fila.motivo, 'no le gustó');
        expect(fila.creadoEn, _ahora);
      },
    );

    test('dado que no escribió motivo, la fila se escribe igual y sin motivo', () async {
      await venderElCanvas(cobrado: 0);

      await local.registrar(pedido({'i-hijos': 1}));

      final fila = (await auditoria()).single;
      expect(fila.evento, EventoAuditoriaLocal.devolucionRegistrada);
      expect(fila.uuid, 'd-1');
      expect(fila.motivo, isNull);
    });

    test('dado dos devoluciones, deja una fila por cada una, en orden', () async {
      await venderElCanvas(cobrado: 0);

      await local.registrar(pedido({'i-hijos': 1}, motivo: 'uno'));
      await local.registrar(pedido({'i-salud': 1}, id: 'd-2', motivo: 'dos'));

      expect(
        [for (final a in await auditoria()) (a.uuid, a.motivo)],
        [('d-1', 'uno'), ('d-2', 'dos')],
      );
    });

    test('dado el mismo id dos veces (doble toque o reintento), la fila es una sola', () async {
      await venderElCanvas(cobrado: 0);

      await Future.wait([
        local.registrar(pedido({'i-hijos': 1}, motivo: 'x')),
        local.registrar(pedido({'i-hijos': 1}, motivo: 'x')),
      ]);
      await local.registrar(pedido({'i-hijos': 1}, motivo: 'x'));

      expect(await auditoria(), hasLength(1));
    });

    test('dado un pedido rechazado, no deja fila', () async {
      await venderElCanvas();

      await expectLater(
        local.registrar(pedido({'i-hijos': 1})),
        throwsA(isA<DevolucionInvalidaException>()),
      );
      await expectLater(
        local.registrar(
          pedido(
            {'i-hijos': 1},
            queHacer: QueHacerConLaDiferencia.retener,
            ahora: _venta.add(const Duration(hours: 73)),
          ),
        ),
        throwsA(isA<DevolucionFueraDePlazoException>()),
      );

      expect(await auditoria(), isEmpty);
    });

    test('dado que el motor de sync falla, no queda fila y el reintento deja una', () async {
      await venderElCanvas(cobrado: 0);
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(
        local.registrar(pedido({'i-hijos': 1}, motivo: 'x')),
        throwsA(isA<StateError>()),
      );
      expect(await auditoria(), isEmpty);

      encolador.fallarCon = null;
      await local.registrar(pedido({'i-hijos': 1}, motivo: 'x'));

      expect(await auditoria(), hasLength(1));
    });
  });

  group('combos', () {
    Future<void> venderUnCombo() async {
      await ventas.registrar(ventaDe('v-1', monto: 180000), [
        itemDe(
          'i-combo',
          'v-1',
          productoId: null,
          coleccionId: 'col-combo',
          componentes: const [
            ComponenteVendido(productoId: 'p-a'),
            ComponenteVendido(productoId: 'p-b', cantidad: 2),
          ],
          cantidad: 2,
          precio: 90000,
        ),
      ]);
      encolador.encolados.clear();
    }

    test(
      'dado un combo, cuando devuelve una unidad, cada libro vuelve con el renglón del combo',
      () async {
        await venderUnCombo();

        final r = await local.registrar(pedido({'i-combo': 1}));

        expect((await filas()).single.productosDevueltos, [
          {'producto_id': 'p-a', 'cantidad': 1, 'venta_item_id': 'i-combo'},
          {'producto_id': 'p-b', 'cantidad': 2, 'venta_item_id': 'i-combo'},
        ]);
        expect(r.totalCentavos, 90000);
        expect(r.eraTotal, isFalse);
        expect(await saldoDeLaVenta(), 90000);
      },
    );

    test('dado un combo devuelto de a una unidad en dos veces, la segunda es total', () async {
      await venderUnCombo();

      await local.registrar(pedido({'i-combo': 1}));
      final r = await local.registrar(pedido({'i-combo': 1}, id: 'd-2'));

      expect(r.eraTotal, isTrue);
      expect(r.totalCentavos, 0);
      await expectLater(
        local.registrar(pedido({'i-combo': 1}, id: 'd-3')),
        throwsA(isA<DevolucionInvalidaException>()),
      );
      expect(await filas(), hasLength(2));
    });
  });

  group('rechazos', () {
    test('31-02: dado que pagó de más y no eligió, lanza sin_eleccion y no escribe nada', () async {
      await venderElCanvas();

      await expectLater(
        local.registrar(pedido({'i-hijos': 1})),
        throwsA(isA<DevolucionInvalidaException>().having((e) => e.causa, 'causa', 'sin_eleccion')),
      );

      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('31-09: dado nada elegido, lanza sin_productos', () async {
      await venderElCanvas();

      await expectLater(
        local.registrar(pedido({'i-hijos': 0})),
        throwsA(
          isA<DevolucionInvalidaException>().having((e) => e.causa, 'causa', 'sin_productos'),
        ),
      );
      expect(await filas(), isEmpty);
    });

    test('dado más de lo vendido o un renglón ajeno, lanza de_mas', () async {
      await venderElCanvas(cobrado: 0);

      for (final malo in [
        {'i-hijos': 2},
        {'otro': 1},
      ]) {
        await expectLater(
          local.registrar(pedido(malo)),
          throwsA(isA<DevolucionInvalidaException>().having((e) => e.causa, 'causa', 'de_mas')),
        );
      }
      expect(await filas(), isEmpty);
    });

    test('dado que ya volvió el libro, no se puede devolver otra vez', () async {
      await venderElCanvas(cobrado: 0);
      await local.registrar(pedido({'i-hijos': 1}));

      await expectLater(
        local.registrar(pedido({'i-hijos': 1}, id: 'd-2')),
        throwsA(isA<DevolucionInvalidaException>().having((e) => e.causa, 'causa', 'de_mas')),
      );
      expect(await filas(), hasLength(1));
    });

    test('dado una venta que no está o dada de baja, lanza DevolucionSinVentaException', () async {
      await expectLater(
        local.registrar(pedido({'i-hijos': 1}, ventaId: 'v-x')),
        throwsA(isA<DevolucionSinVentaException>()),
      );

      await venderElCanvas();
      await (db.update(db.ventas)).write(VentasCompanion(deletedAt: Value(t0)));
      await expectLater(
        local.registrar(pedido({'i-hijos': 1})),
        throwsA(isA<DevolucionSinVentaException>()),
      );
      expect(await filas(), isEmpty);
    });

    test('31-08: dado que pasaron más de 72 h, lanza DevolucionFueraDePlazoException', () async {
      await venderElCanvas(cobrado: 0);

      await expectLater(
        local.registrar(
          pedido({'i-hijos': 1}, ahora: _venta.add(const Duration(hours: 72, milliseconds: 1))),
        ),
        throwsA(isA<DevolucionFueraDePlazoException>()),
      );
      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('dado que pasaron 72 h justas, todavía la registra', () async {
      await venderElCanvas(cobrado: 0);

      await local.registrar(pedido({'i-hijos': 1}, ahora: _venta.add(const Duration(hours: 72))));

      expect(await filas(), hasLength(1));
    });

    test(
      'dado que el motor de sync falla, no queda nada guardado y el reintento la registra',
      () async {
        await venderElCanvas(cobrado: 0);
        encolador.fallarCon = StateError('motor apagado');

        await expectLater(local.registrar(pedido({'i-hijos': 1})), throwsA(isA<StateError>()));
        expect(await filas(), isEmpty);

        encolador.fallarCon = null;
        final r = await local.registrar(pedido({'i-hijos': 1}));

        expect(r.yaEstaba, isFalse);
        expect(await filas(), hasLength(1));
      },
    );
  });

  group('idempotencia', () {
    test(
      'dado la misma devolución dos veces, escribe una sola y la segunda dice que ya estaba',
      () async {
        await venderElCanvas(cobrado: 0);
        await local.registrar(pedido({'i-hijos': 1}));
        encolador.encolados.clear();

        final otra = await local.registrar(pedido({'i-hijos': 1}));

        expect(otra.yaEstaba, isTrue);
        expect(otra.devolucion.id, 'd-1');
        expect(await filas(), hasLength(1));
        expect(encolador.encolados, isEmpty);
      },
    );

    test('dado un doble toque, cuando dos pedidos llegan juntos, una sola escribe', () async {
      await venderElCanvas(cobrado: 0);

      final r = await Future.wait([
        local.registrar(pedido({'i-hijos': 1})),
        local.registrar(pedido({'i-hijos': 1})),
      ]);

      expect(await filas(), hasLength(1));
      expect(r.where((e) => e.yaEstaba), hasLength(1));
      expect(cola().where((c) => c == 'devolucion:insert'), hasLength(1));
    });

    test(
      'dado dos devoluciones distintas juntas del mismo libro, la segunda no devuelve de más',
      () async {
        await venderElCanvas(cobrado: 0);

        Future<Object> intentar(Future<Object> f) async {
          try {
            return await f;
          } on Object catch (e) {
            return e;
          }
        }

        final resultados = await Future.wait([
          intentar(local.registrar(pedido({'i-hijos': 1}))),
          intentar(local.registrar(pedido({'i-hijos': 1}, id: 'd-2'))),
        ]);

        expect(await filas(), hasLength(1));
        expect(resultados.whereType<DevolucionInvalidaException>(), hasLength(1));
      },
    );

    test('dado dos devoluciones seguidas de renglones distintos, se suman sin pisarse', () async {
      await venderElCanvas(cobrado: 0);

      await local.registrar(pedido({'i-hijos': 1}));
      final r = await local.registrar(pedido({'i-salud': 1}, id: 'd-2'));

      expect(await filas(), hasLength(2));
      expect(r.eraTotal, isTrue);
      expect(r.totalCentavos, 0);
    });
  });

  group('lectura de la venta', () {
    test('dado una venta sin devoluciones, lee sus renglones con el precio de la foto', () async {
      await venderElCanvas();

      final v = (await local.ventaParaDevolver('v-1'))!;

      expect(v.numeroTalonario, 'T-100');
      expect(v.montoTotalCentavos, 450000);
      expect(v.cobradoCentavos, 450000);
      expect([
        for (final r in v.renglones) (r.ventaItemId, r.cantidad, r.unidadesDevueltas),
      ], unorderedEquals([('i-salud', 1, 0), ('i-hijos', 1, 0)]));
      expect(v.renglones.first.titulo, isNotEmpty);
    });

    test('dado una venta con una devolución, lee lo ya devuelto, reembolsado y retenido', () async {
      await venderElCanvas();
      await local.registrar(
        pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.devolverAhora),
      );

      final v = (await local.ventaParaDevolver('v-1'))!;

      expect(v.renglones.singleWhere((r) => r.ventaItemId == 'i-hijos').unidadesDevueltas, 1);
      expect(v.reembolsadoCentavos, 190000);
      expect(v.seQuedaConCentavos, 260000);
      expect(v.saldoCentavos, 0);
      expect(v.estaTodoDevuelto, isFalse);
    });

    test('dado una venta que no está, la lectura es null', () async {
      expect(await local.ventaParaDevolver('v-x'), isNull);
    });

    test('dado una devolución dada de baja, la venta vuelve a como estaba', () async {
      await venderElCanvas(cobrado: 0);
      await local.registrar(pedido({'i-hijos': 1}));
      await (db.update(db.devoluciones)).write(DevolucionesCompanion(deletedAt: Value(_ahora)));

      final v = (await local.ventaParaDevolver('v-1'))!;

      expect(v.unidadesDisponibles, 2);
      expect(await saldoDeLaVenta(), 450000);
    });
  });

  group('saldo (HU-COB-005)', () {
    test(
      'dado una devolución parcial, el saldo de la venta, de la persona, de la casa y total bajan',
      () async {
        await venderElCanvas(cobrado: 100000);
        expect(await saldoDeLaVenta(), 350000);

        await local.registrar(pedido({'i-hijos': 1}));

        expect(await saldoDeLaVenta(), 160000);
        expect(await cobranzas.observarSaldoDePersona('per-1').first, 160000);
        expect(await cobranzas.observarSaldoDeUbicacion('ub-1').first, 160000);
        expect(await cobranzas.observarSaldoTotal('col-1').first, 160000);
        expect(await cobranzas.saldosPorPersona(['per-1']), {'per-1': 160000});
      },
    );

    test('dado una devolución total, la persona deja de deber', () async {
      await venderElCanvas(cobrado: 100000);

      await local.registrar(
        pedido({'i-salud': 1, 'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.retener),
      );

      expect(await saldoDeLaVenta(), 0);
      expect(await cobranzas.saldosPorPersona(['per-1']), isEmpty);
      expect(await cobranzas.observarSaldoTotal('col-1').first, 0);
    });

    test('dado que el saldo se observa, una devolución lo actualiza sin recargar', () async {
      await venderElCanvas(cobrado: 100000);
      final valores = <int>[];
      final sub = cobranzas.observarSaldoDePersona('per-1').listen(valores.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await local.registrar(pedido({'i-hijos': 1}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(valores, [350000, 160000]);
    });

    test(
      'dado que pagó de más y quedó «Debo al cliente», la venta lo dice y no hay saldo',
      () async {
        await venderElCanvas();
        await local.registrar(
          pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.devolverDespues),
        );

        final v = (await cobranzas.ventaConSaldo('v-1'))!;

        expect(v.saldoCentavos, 0);
        expect(v.deboAlClienteCentavos, 190000);
        expect(v.seQuedaConCentavos, 260000);
        expect(v.tieneSaldo, isFalse);
      },
    );

    test('dado el saldo nuevo, un cobro por más que ese saldo se rechaza', () async {
      await venderElCanvas(cobrado: 100000);
      await local.registrar(pedido({'i-hijos': 1}));

      await expectLater(cobrar(160001, id: 'c-2'), throwsA(isA<CobroMayorAlSaldoException>()));
      await cobrar(160000, id: 'c-3');

      expect(await saldoDeLaVenta(), 0);
    });
  });

  group('la casa (R-UB08)', () {
    test('dado una devolución parcial, la casa sigue pendiente de entrega y cobranza', () async {
      await venderElCanvas();

      await local.registrar(pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.retener));

      expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
    });

    test('dado una devolución parcial de lo que faltaba entregar, la venta pagada y entregada '
        'queda completa', () async {
      await venderElCanvas();
      await entregas.entregarAhora(
        'v-1',
        colportorId: 'col-1',
        ahora: _ahora,
        generarId: () => 'e-${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(await colorDeLaCasa(), 'VENTA_COMPLETA');

      await local.registrar(
        pedido({'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.devolverAhora),
      );

      // Lo vendido neto sigue entregado y pagado: la casa no cambia.
      expect(await colorDeLaCasa(), 'VENTA_COMPLETA');
    });

    test(
      'ADR-003: dado una devolución total, la casa vuelve a verde liso (entrevista dada)',
      () async {
        await venderElCanvas();
        expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');

        final r = await local.registrar(
          pedido({'i-salud': 1, 'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.retener),
        );

        expect(await colorDeLaCasa(), 'ENTREVISTA_SIN_VENTA');
        expect(r.colorDeLaCasa?.codigo, 'ENTREVISTA_SIN_VENTA');
        expect(r.eraTotal, isTrue);
      },
    );

    test('dado una devolución total, la casa en la cola cambia con un house_status', () async {
      await venderElCanvas();

      await local.registrar(
        pedido({'i-salud': 1, 'i-hijos': 1}, queHacer: QueHacerConLaDiferencia.retener),
      );

      expect(cola(), ['devolucion:insert', 'house_status:update']);
    });

    test(
      'dado que se baja la devolución total y se recalcula, la casa vuelve a pendiente',
      () async {
        await venderElCanvas(cobrado: 0);
        await local.registrar(pedido({'i-salud': 1, 'i-hijos': 1}));
        await (db.update(db.devoluciones)).write(DevolucionesCompanion(deletedAt: Value(_ahora)));
        final casas = HouseStatusUpdaterDrift(db, encolador: encolador);

        await casas.recalcular('ub-1', ahora: _ahora, colportorId: 'col-1');

        expect(await colorDeLaCasa(), 'ENTREGA_Y_COBRANZA_PENDIENTE');
      },
    );
  });

  group('la entrega neta', () {
    test(
      'dado un libro devuelto, lo vendido para entregar baja y deja de faltar entregarlo',
      () async {
        await venderElCanvas(cobrado: 0);
        expect(await EstadoDeEntrega.vendidoDe(db, 'v-1'), {'p-salud': 1, 'p-hijos': 1});

        await local.registrar(pedido({'i-hijos': 1}));

        expect(await EstadoDeEntrega.vendidoDe(db, 'v-1'), {'p-salud': 1});
      },
    );

    test('dado que se entregó lo que quedó, la venta cuenta como entregada', () async {
      await venderElCanvas(cobrado: 0);
      await local.registrar(pedido({'i-hijos': 1}));

      final r = await entregas.entregarAhora(
        'v-1',
        colportorId: 'col-1',
        ahora: _ahora,
        generarId: () => 'e-1',
      );

      expect([for (final e in r.entregas) (e.productoId, e.cantidad)], [('p-salud', 1)]);
      expect(await EstadoDeEntrega.estaEntregada(db, 'v-1'), isTrue);
    });
  });
}
