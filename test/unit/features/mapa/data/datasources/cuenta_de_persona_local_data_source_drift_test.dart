// Las entregas, los cobros y la cuenta de una persona (HU-UBI-009, #403) contra las tablas reales en
// memoria: lo que va al historial de la ficha, lo que suma la cuenta (comprado, entregado, pagado y
// saldo) y que todo se mantiene al día cuando cambia una venta, una entrega o un cobro.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/cuenta_de_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CuentaDePersonaLocalDataSourceDrift fuente;

  Future<void> sembrarPersona(String id) => db
      .into(db.personas)
      .insert(PersonasCompanion.insert(id: id, nombre: 'María', createdAt: t0, updatedAt: t0));

  Future<void> sembrarProducto(String id, String nombre) => db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          id: id,
          nombre: nombre,
          tipo: 'LIBRO',
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> venta(
    String id, {
    String vinculo = 'ep-1',
    String talonario = '0042',
    int monto = 120000,
    DateTime? fecha,
    DateTime? borrada,
  }) => db
      .into(db.ventas)
      .insert(
        VentasCompanion.insert(
          id: id,
          espacioPersonaId: vinculo,
          numeroTalonario: talonario,
          montoTotal: monto,
          fecha: fecha ?? DateTime.utc(2026, 10, 12, 14),
          colportorId: 'col-1',
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  Future<void> renglon(String id, String ventaId, String producto, {int cantidad = 1}) => db
      .into(db.ventaItems)
      .insert(
        VentaItemsCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: Value(producto),
          cantidad: cantidad,
          precioUnitario: 1000,
          subtotal: 1000 * cantidad,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> entrega(
    String id,
    String ventaId,
    String producto, {
    int cantidad = 1,
    DateTime? cuando,
    bool pendiente = false,
    DateTime? borrada,
    DateTime? creada,
  }) => db
      .into(db.entregas)
      .insert(
        EntregasCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: producto,
          cantidad: cantidad,
          pendiente: Value(pendiente),
          fechaEntrega: Value(pendiente ? null : (cuando ?? DateTime.utc(2026, 10, 13, 15))),
          createdAt: creada ?? t0,
          updatedAt: creada ?? t0,
          deletedAt: Value(borrada),
        ),
      );

  Future<void> cobro(
    String id,
    String ventaId, {
    int monto = 60000,
    String medio = 'EFECTIVO',
    DateTime? fecha,
    DateTime? borrado,
  }) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: ventaId,
          monto: monto,
          medio: medio,
          fecha: fecha ?? DateTime.utc(2026, 10, 20, 16),
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrado),
        ),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    fuente = CuentaDePersonaLocalDataSourceDrift(db);
    await sembrarCasa(db);
    await sembrarPersona('per-1');
  });
  tearDown(() => db.close());

  group('movimientos (el historial)', () {
    test('sin ventas, entregas ni cobros no hay nada', () async {
      expect(await fuente.movimientos('per-1'), isEmpty);
    });

    test('un cobro en efectivo lleva el monto, el medio y el talonario de su venta', () async {
      await venta('ven-1', talonario: '0042');
      await cobro('cob-1', 'ven-1', fecha: DateTime.utc(2026, 10, 20, 16));

      final cobroEnFicha = (await fuente.movimientos('per-1')).single as CobroEnFicha;

      expect(cobroEnFicha.id, 'cob-1');
      expect(cobroEnFicha.fecha, DateTime.utc(2026, 10, 20, 16));
      expect(cobroEnFicha.montoCentavos, 60000);
      expect(cobroEnFicha.efectivo, isTrue);
      expect(cobroEnFicha.numeroTalonario, '0042');
    });

    test('un cobro con tarjeta o por transferencia no se dice «en efectivo»', () async {
      await venta('ven-1');
      await cobro('cob-t', 'ven-1', medio: 'TARJETA');
      await cobro('cob-x', 'ven-1', medio: 'TRANSFERENCIA');

      final cobros = (await fuente.movimientos('per-1')).cast<CobroEnFicha>();

      expect(cobros, hasLength(2));
      expect(cobros.every((c) => !c.efectivo), isTrue);
    });

    test(
      'las filas de una entrega inmediata (un combo) son una sola tarjeta con sus líneas',
      () async {
        await venta('ven-1');
        await sembrarProducto('pro-1', 'Salud y Hogar');
        await sembrarProducto('pro-2', 'Nuestros Hijos');
        final cuando = DateTime.utc(2026, 10, 13, 15);
        await entrega('ent-a', 'ven-1', 'pro-1', cantidad: 2, cuando: cuando);
        await entrega('ent-b', 'ven-1', 'pro-2', cuando: cuando);

        final entregaEnFicha = (await fuente.movimientos('per-1')).single as EntregaEnFicha;

        expect(entregaEnFicha.id, 'ent-a');
        expect(entregaEnFicha.fecha, cuando);
        expect(entregaEnFicha.pendiente, isFalse);
        expect(entregaEnFicha.lineas, const [
          LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 2),
          LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1),
        ]);
      },
    );

    test('dos entregas de la misma venta en momentos distintos son dos tarjetas', () async {
      await venta('ven-1');
      await sembrarProducto('pro-1', 'Salud y Hogar');
      await entrega('ent-1', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 13, 15));
      await entrega('ent-2', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 18, 15));

      expect((await fuente.movimientos('per-1')).map((m) => m.id), ['ent-2', 'ent-1']);
    });

    test('un producto que el catálogo no trae queda como «Producto»', () async {
      await venta('ven-1');
      await entrega('ent-1', 'ven-1', 'pro-que-no-esta');

      final e = (await fuente.movimientos('per-1')).single as EntregaEnFicha;

      expect(e.lineas.single.nombre, 'Producto');
    });

    test(
      'las entregas pendientes todavía no se arman (su fecha prevista llega con HU-VEN-003)',
      () async {
        await venta('ven-1');
        await entrega('ent-1', 'ven-1', 'pro-1', pendiente: true);

        expect(await fuente.movimientos('per-1'), isEmpty);
      },
    );

    test('lo dado de baja no aparece: entregas, cobros y los de una venta borrada', () async {
      await venta('ven-1');
      await venta('ven-borrada', talonario: '0099', borrada: t0);
      await entrega('ent-borrada', 'ven-1', 'pro-1', borrada: t0);
      await cobro('cob-borrado', 'ven-1', borrado: t0);
      await cobro('cob-de-venta-borrada', 'ven-borrada');
      await entrega('ent-de-venta-borrada', 'ven-borrada', 'pro-1');

      expect(await fuente.movimientos('per-1'), isEmpty);
    });

    test('lo de otra persona no se mezcla', () async {
      await sembrarPersona('per-2');
      await sembrarVinculo(db, id: 'ep-9', personaId: 'per-2');
      await venta('ven-de-otra', vinculo: 'ep-9');
      await cobro('cob-de-otra', 'ven-de-otra');
      await entrega('ent-de-otra', 'ven-de-otra', 'pro-1');

      expect(await fuente.movimientos('per-1'), isEmpty);
      expect(await fuente.movimientos('per-2'), hasLength(2));
    });

    test('la persona en un depto dado de baja sigue viendo lo que pasó ahí', () async {
      await sembrarEspacio(db, id: 'esp-3', numeroDepto: '3B');
      await sembrarVinculo(db, id: 'ep-3', espacioId: 'esp-3', borrado: t0);
      await venta('ven-1');
      await venta('ven-vieja', vinculo: 'ep-3', talonario: '0001');
      await cobro('cob-1', 'ven-1');
      await cobro('cob-viejo', 'ven-vieja');

      expect(
        (await fuente.movimientos('per-1')).map((m) => m.id),
        containsAll(['cob-1', 'cob-viejo']),
      );
    });

    test('van del más nuevo al más viejo, y a igual fecha por id', () async {
      await venta('ven-1');
      await cobro('cob-a', 'ven-1', monto: 100, fecha: DateTime.utc(2026, 10, 20, 16));
      await cobro('cob-b', 'ven-1', monto: 100, fecha: DateTime.utc(2026, 10, 22, 16));
      await entrega('ent-1', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 21, 16));
      await cobro('cob-c', 'ven-1', monto: 100, fecha: DateTime.utc(2026, 10, 20, 16));

      expect((await fuente.movimientos('per-1')).map((m) => m.id), [
        'cob-b',
        'ent-1',
        'cob-c',
        'cob-a',
      ]);
    });

    test('se mantiene al día: un cobro o una entrega nuevos salen sin volver a pedir', () async {
      await venta('ven-1');
      final llegadas = <List<MovimientoDeFicha>>[];
      final sub = fuente.observarMovimientos('per-1').listen(llegadas.add);
      await pumpEventQueue();
      expect(llegadas.last, isEmpty);

      await cobro('cob-1', 'ven-1');
      await pumpEventQueue();
      expect(llegadas.last.map((m) => m.id), ['cob-1']);

      await entrega('ent-1', 'ven-1', 'pro-1', cuando: DateTime.utc(2026, 10, 25, 9));
      await pumpEventQueue();
      expect(llegadas.last.map((m) => m.id), ['ent-1', 'cob-1']);

      await sub.cancel();
    });

    test('un cambio que no toca a la persona no repite la lista', () async {
      await venta('ven-1');
      await cobro('cob-1', 'ven-1');
      final llegadas = <List<MovimientoDeFicha>>[];
      final sub = fuente.observarMovimientos('per-1').listen(llegadas.add);
      await pumpEventQueue();
      final antes = llegadas.length;

      await sembrarProducto('pro-nuevo', 'Otro libro');
      await pumpEventQueue();

      expect(llegadas, hasLength(antes));
      await sub.cancel();
    });

    test('una venta con 100 cobros y 100 entregas se lee entera', () async {
      await venta('ven-1', monto: 10000000);
      for (var i = 0; i < 100; i++) {
        await cobro('cob-${i.toString().padLeft(3, '0')}', 'ven-1', monto: 100);
        await entrega(
          'ent-${i.toString().padLeft(3, '0')}',
          'ven-1',
          'pro-1',
          cuando: DateTime.utc(2026, 10, 13, 15).add(Duration(minutes: i)),
        );
      }

      expect(await fuente.movimientos('per-1'), hasLength(200));
    });
  });

  group('resumen (la cuenta)', () {
    test('sin ventas no hay cuenta', () async {
      expect(await fuente.resumenDe('per-1'), isNull);
    });

    test('una venta sin cobros ni entregas: debe todo y no entregó nada', () async {
      await venta('ven-1', monto: 120000);
      await sembrarProducto('pro-1', 'Salud y Hogar');
      await renglon('it-1', 'ven-1', 'pro-1');

      expect(
        await fuente.resumenDe('per-1'),
        const ResumenCuentaPersona(
          compradoCentavos: 120000,
          pagadoCentavos: 0,
          saldoCentavos: 120000,
          entregasHechas: 0,
          entregasTotales: 1,
        ),
      );
    });

    test('suma lo comprado, lo pagado y lo que falta, y cuenta las ventas entregadas', () async {
      await venta('ven-1', monto: 120000);
      await venta('ven-2', monto: 60000, talonario: '0043');
      await renglon('it-1', 'ven-1', 'pro-1');
      await renglon('it-2', 'ven-2', 'pro-2');
      await entrega('ent-1', 'ven-1', 'pro-1');
      await cobro('cob-1', 'ven-1', monto: 60000);
      await cobro('cob-2', 'ven-1', monto: 20000);

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.compradoCentavos, 180000);
      expect(r.pagadoCentavos, 80000);
      expect(r.saldoCentavos, 100000);
      expect(r.entregasHechas, 1);
      expect(r.entregasTotales, 2);
      expect(r.entregasPendientes, 1);
      expect(r.tieneSaldo, isTrue);
    });

    test('una venta cobrada de más no resta de lo que debe otra', () async {
      await venta('ven-1', monto: 50000);
      await venta('ven-2', monto: 60000, talonario: '0043');
      await cobro('cob-1', 'ven-1', monto: 70000);

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.pagadoCentavos, 70000);
      expect(r.saldoCentavos, 60000);
    });

    test(
      'una venta pagada entera y entregada entera no deja saldo ni entregas pendientes',
      () async {
        await venta('ven-1', monto: 50000);
        await renglon('it-1', 'ven-1', 'pro-1', cantidad: 2);
        await entrega('ent-1', 'ven-1', 'pro-1', cantidad: 2);
        await cobro('cob-1', 'ven-1', monto: 50000);

        final r = (await fuente.resumenDe('per-1'))!;

        expect(r.saldoCentavos, 0);
        expect(r.tieneSaldo, isFalse);
        expect(r.entregasHechas, 2);
        expect(r.entregasPendientes, 0);
      },
    );

    test('una entrega parcial cuenta las unidades entregadas sobre las vendidas', () async {
      await venta('ven-1');
      await renglon('it-1', 'ven-1', 'pro-1', cantidad: 3);
      await entrega('ent-1', 'ven-1', 'pro-1', cantidad: 2);

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.entregasHechas, 2);
      expect(r.entregasTotales, 3);
    });

    test('entregar de más un producto no suma de más ni tapa lo que falta de otro', () async {
      await venta('ven-1');
      await renglon('it-1', 'ven-1', 'pro-1');
      await renglon('it-2', 'ven-1', 'pro-2', cantidad: 2);
      await entrega('ent-1', 'ven-1', 'pro-1', cantidad: 5);

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.entregasHechas, 1);
      expect(r.entregasTotales, 3);
      expect(r.entregasPendientes, 2);
    });

    test('suma las unidades de todas las ventas de la persona (canvas: «Entregado 1 de 2»)', () async {
      await venta('ven-1');
      await venta('ven-2', talonario: '0043');
      await renglon('it-1', 'ven-1', 'pro-1');
      await renglon('it-2', 'ven-2', 'pro-2');
      await entrega('ent-1', 'ven-1', 'pro-1');

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.entregasHechas, 1);
      expect(r.entregasTotales, 2);
    });

    test('una fila pendiente o dada de baja no cuenta como entregada', () async {
      await venta('ven-1');
      await renglon('it-1', 'ven-1', 'pro-1');
      await entrega('ent-p', 'ven-1', 'pro-1', pendiente: true);
      await entrega('ent-b', 'ven-1', 'pro-1', borrada: t0);

      expect((await fuente.resumenDe('per-1'))!.entregasHechas, 0);
    });

    test('una venta sin renglones no entra en las entregas (no hay nada que entregar)', () async {
      await venta('ven-1', monto: 50000);

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.entregasTotales, 0);
      expect(r.compradoCentavos, 50000);
    });

    test('lo dado de baja no suma: la venta, sus cobros y los cobros borrados', () async {
      await venta('ven-1', monto: 50000);
      await venta('ven-borrada', monto: 99999, talonario: '0099', borrada: t0);
      await cobro('cob-borrado', 'ven-1', monto: 40000, borrado: t0);
      await cobro('cob-de-venta-borrada', 'ven-borrada', monto: 99999);

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.compradoCentavos, 50000);
      expect(r.pagadoCentavos, 0);
      expect(r.saldoCentavos, 50000);
    });

    test('lo de otra persona no se mezcla', () async {
      await sembrarPersona('per-2');
      await sembrarVinculo(db, id: 'ep-9', personaId: 'per-2');
      await venta('ven-de-otra', vinculo: 'ep-9', monto: 77700);

      expect(await fuente.resumenDe('per-1'), isNull);
      expect((await fuente.resumenDe('per-2'))!.compradoCentavos, 77700);
    });

    test('suma también las ventas de un depto dado de baja (como el historial)', () async {
      await sembrarEspacio(db, id: 'esp-3', numeroDepto: '3B');
      await sembrarVinculo(db, id: 'ep-3', espacioId: 'esp-3', borrado: t0);
      await venta('ven-1', monto: 50000);
      await venta('ven-vieja', vinculo: 'ep-3', monto: 30000, talonario: '0001');

      final r = (await fuente.resumenDe('per-1'))!;

      expect(r.compradoCentavos, 80000);
      expect(r.saldoCentavos, 80000);
    });

    test('un combo se entrega por sus componentes', () async {
      await venta('ven-1');
      await db
          .into(db.colecciones)
          .insert(
            ColeccionesCompanion.insert(
              id: 'col-1',
              nombre: 'Nuestros Hijos',
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      await db
          .into(db.ventaItems)
          .insert(
            VentaItemsCompanion.insert(
              id: 'it-combo',
              ventaId: 'ven-1',
              coleccionId: const Value('col-1'),
              cantidad: 2,
              precioUnitario: 1000,
              subtotal: 2000,
              componentes: const Value([
                {'producto_id': 'pro-1', 'cantidad': 1},
                {'producto_id': 'pro-2', 'cantidad': 1},
              ]),
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      await entrega('ent-1', 'ven-1', 'pro-1', cantidad: 2);

      expect((await fuente.resumenDe('per-1'))!.entregasHechas, 2);

      await entrega('ent-2', 'ven-1', 'pro-2', cantidad: 2);

      expect((await fuente.resumenDe('per-1'))!.entregasHechas, 4);
    });
  });
}
