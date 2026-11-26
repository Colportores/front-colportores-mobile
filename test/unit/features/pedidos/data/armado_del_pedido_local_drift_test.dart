// Lo que se ve al armar el pedido, contra la base real (#387): los productos con su costo y su stock, lo que
// falta entregar y el límite de la campaña.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/pedidos/data/datasources/armado_del_pedido_local_drift.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

final _t = DateTime.utc(2026, 11, 1);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ArmadoDelPedidoLocalDrift armado;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    armado = ArmadoDelPedidoLocalDrift(db);
  });
  tearDown(() => db.close());

  Future<void> producto(
    String id,
    String nombre, {
    String? categoria,
    int? precio = 10000,
    bool bonificable = false,
    bool borrado = false,
  }) => db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          id: id,
          nombre: nombre,
          esBonificable: Value(bonificable),
          precioBaseCompra: Value(precio),
          categoria: Value(categoria),
          createdAt: _t,
          updatedAt: _t,
          deletedAt: Value(borrado ? _t : null),
        ),
      );

  Future<void> stock(String productoId, int cantidad, {String usuario = 'col-1'}) => db
      .into(db.stocks)
      .insert(
        StocksCompanion.insert(
          id: 's-$productoId-$usuario',
          usuarioId: usuario,
          productoId: productoId,
          cantidadDisponible: Value(cantidad),
          createdAt: _t,
          updatedAt: _t,
        ),
      );

  group('productos', () {
    test(
      'dado el catálogo, entonces ofrece libros, misioneros y revistas con precio, por nombre, con su stock',
      () async {
        await producto('a', 'Zeta', categoria: 'BONIFICABLES', bonificable: true);
        await producto('b', 'Beta', categoria: 'ESPIRITUALES');
        await producto('c', 'Camino', categoria: 'MISIONEROS');
        await producto('d', 'Diario', categoria: 'REVISTAS');
        await stock('a', 2);
        await stock('c', -3, usuario: 'col-1');
        await stock('d', 9, usuario: 'otra');
        final lista = await armado.observarProductos('col-1').first;
        expect(lista.map((p) => p.nombre), ['Beta', 'Camino', 'Diario', 'Zeta']);
        expect(lista.map((p) => p.categoria), [
          CategoriaDelPedido.libros,
          CategoriaDelPedido.misioneros,
          CategoriaDelPedido.revistas,
          CategoriaDelPedido.libros,
        ]);
        final porNombre = {for (final p in lista) p.nombre: p};
        expect(porNombre['Zeta']!.stock, 2);
        expect(porNombre['Camino']!.stock, -3, reason: 'el stock puede ser negativo (S46)');
        expect(porNombre['Diario']!.stock, 0, reason: 'el stock de otra colportora no cuenta');
        expect(porNombre['Beta']!.stock, 0, reason: 'sin fila de stock, 0');
        expect(porNombre['Zeta']!.precioDeCompraCentavos, 10000);
      },
    );

    test(
      'dados categoría desconocida o sin categoría, sin precio de compra o dado de baja, entonces no se ofrecen',
      () async {
        await producto('n', 'Sin categoría');
        await producto('x', 'Rara', categoria: 'NUEVA');
        await producto('p', 'Sin precio', categoria: 'REVISTAS', precio: null);
        await producto('q', 'Precio cero', categoria: 'REVISTAS', precio: 0);
        await producto('r', 'Borrado', categoria: 'REVISTAS', borrado: true);
        await producto('ok', 'Bueno', categoria: 'REVISTAS');
        final lista = await armado.observarProductos('col-1').first;
        expect(lista.map((p) => p.id), ['ok']);
      },
    );

    test(
      'el material de trabajo se ofrece como «Materiales», con su costo y su stock (#769)',
      () async {
        await producto('m', 'Cuaderno de ruta', categoria: 'MATERIAL', precio: 25000);
        await stock('m', 3);
        final lista = await armado.observarProductos('col-1').first;
        expect(lista.map((p) => (p.id, p.categoria)), [('m', CategoriaDelPedido.materiales)]);
        expect(lista.single.precioDeCompraCentavos, 25000);
        expect(lista.single.stock, 3);
      },
    );

    test('dado que cambia el stock, entonces el stream emite de nuevo', () async {
      await producto('a', 'Uno', categoria: 'REVISTAS');
      final emisiones = <int>[];
      final sub = armado.observarProductos('col-1').listen((l) => emisiones.add(l.single.stock));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await stock('a', 7);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await sub.cancel();
      expect(emisiones.first, 0);
      expect(emisiones.last, 7);
    });

    test('los nombres incluyen también los productos que no se pueden pedir', () async {
      await producto('m', 'Material', categoria: 'MATERIAL');
      expect(await armado.observarNombres().first, {'m': 'Material'});
    });
  });

  group('libros por entregar', () {
    Future<void> venta(String id, {String colportor = 'col-1', bool borrada = false}) => db
        .into(db.ventas)
        .insert(
          VentasCompanion.insert(
            id: id,
            espacioPersonaId: 'ep-1',
            numeroTalonario: 'T-$id',
            montoTotal: 1000,
            fecha: _t,
            colportorId: colportor,
            createdAt: _t,
            updatedAt: _t,
            deletedAt: Value(borrada ? _t : null),
          ),
        );
    Future<void> entrega(String id, String ventaId, int cantidad, {bool pendiente = true}) => db
        .into(db.entregas)
        .insert(
          EntregasCompanion.insert(
            id: id,
            ventaId: ventaId,
            productoId: 'a',
            cantidad: cantidad,
            pendiente: Value(pendiente),
            createdAt: _t,
            updatedAt: _t,
          ),
        );

    test(
      'dadas entregas pendientes y entregadas, entonces suma solo las pendientes de sus ventas',
      () async {
        await venta('v1');
        await venta('v2');
        await venta('v3', colportor: 'otra');
        await venta('v4', borrada: true);
        await entrega('e1', 'v1', 3);
        await entrega('e2', 'v1', 5, pendiente: false);
        await entrega('e3', 'v2', 1);
        await entrega('e4', 'v3', 9);
        await entrega('e5', 'v4', 7);
        final c = await armado.observarContexto('col-1', _t).first;
        expect(c.librosPorEntregar, 4);
      },
    );

    test('dado que no vendió nada, entonces son 0 y no hay límite', () async {
      final c = await armado.observarContexto('col-1', _t).first;
      expect(c.librosPorEntregar, 0);
      expect(c.limiteDeudaCentavos, isNull);
    });
  });

  group('el límite de la campaña', () {
    Future<void> campania(String id, String inicio, String? fin, int? limite) => db
        .into(db.campanias)
        .insert(
          CampaniasCompanion.insert(
            id: id,
            nombre: id,
            fechaInicio: inicio,
            fechaFin: Value(fin),
            limiteDeuda: Value(limite),
            createdAt: _t,
            updatedAt: _t,
          ),
        );
    Future<void> inscripta(String campaniaId, {String usuario = 'col-1'}) => db
        .into(db.campaniasColportor)
        .insert(
          CampaniasColportorCompanion.insert(
            id: 'cc-$campaniaId-$usuario',
            campaniaId: campaniaId,
            usuarioId: usuario,
            createdAt: _t,
            updatedAt: _t,
          ),
        );

    Future<int?> limiteEl(DateTime hoy) async =>
        (await armado.observarContexto('col-1', hoy).first).limiteDeudaCentavos;

    test('dada la campaña en curso con límite, entonces es el suyo (en centavos)', () async {
      await campania('c1', '2026-09-01', '2026-12-15', 3000000);
      await inscripta('c1');
      expect(await limiteEl(DateTime.utc(2026, 11, 23, 15)), 3000000);
    });

    test('dada una campaña sin límite, entonces no hay aviso (null)', () async {
      await campania('c1', '2026-09-01', '2026-12-15', null);
      await inscripta('c1');
      expect(await limiteEl(DateTime.utc(2026, 11, 23, 15)), isNull);
    });

    test('dadas dos campañas en curso, entonces gana la que empezó última', () async {
      await campania('vieja', '2026-01-01', null, 1000000);
      await campania('nueva', '2026-10-01', '2026-12-31', 2000000);
      await inscripta('vieja');
      await inscripta('nueva');
      expect(await limiteEl(DateTime.utc(2026, 11, 23, 15)), 2000000);
    });

    test(
      'dada una campaña que terminó hace menos de 15 días, entonces todavía vale; pasados los 15, no',
      () async {
        await campania('c1', '2026-09-01', '2026-11-10', 4000000);
        await inscripta('c1');
        expect(
          await limiteEl(DateTime.utc(2026, 11, 25, 15)),
          4000000,
          reason: '10/11 + 15 = 25/11',
        );
        expect(await limiteEl(DateTime.utc(2026, 11, 26, 15)), isNull);
      },
    );

    test(
      'dada una campaña por empezar a la que ya está inscripta, entonces se puede pedir y vale su límite',
      () async {
        await campania('futura', '2026-12-01', '2027-02-28', 5000000);
        await inscripta('futura');
        expect(await limiteEl(DateTime.utc(2026, 11, 23, 15)), 5000000);
      },
    );

    test('dada la inscripción de otra colportora, entonces no cuenta', () async {
      await campania('c1', '2026-09-01', '2026-12-15', 3000000);
      await inscripta('c1', usuario: 'otra');
      expect(await limiteEl(DateTime.utc(2026, 11, 23, 15)), isNull);
    });
  });
}
