// Los estados de «No se envió» (#748) para el QA: el canvas 37 no dibuja este estado, así que cada uno sale
// del issue y se compara con las piezas vecinas (37B·01 y 37B·03). Los usan las guías de accesibilidad y las
// capturas.
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cuenta_arnes.dart' show montarCuenta;
import 'pedidos_arnes.dart';
import 'pedidos_falsos.dart';

typedef MontarEstado748 = Future<void> Function(WidgetTester t, Size tamano, double escala);

const telefonoChico748 = Size(360, 640);
const telefonoGrande748 = Size(412, 915);

Pedido noSeEnvio748({
  String id = 'ped-1',
  CausaDelRechazoAlEnviar causa = CausaDelRechazoAlEnviar.fueraDeLaCampania,
  DateTime? fecha,
  int montoCentavos = 1184000,
  List<LineaDelPedido>? lineas,
}) => pedidoDe(
  id: id,
  estado: EstadoDelPedido.noSeEnvio,
  rechazoAlEnviar: causa,
  fecha: fecha ?? DateTime(2026, 11, 23, 9, 30),
  montoCentavos: montoCentavos,
  lineas: lineas,
);

Future<void> _cuenta(WidgetTester t, List<Pedido> pedidos, Size s, double e) async {
  final arnes = ArnesDePedidos(pedidos: PedidosFalsos(pedidos));
  await montarCuenta(
    t,
    arnes.cuenta,
    tamano: s,
    escala: e,
    overrides: arnes.overrides(conCuenta: false),
  );
  await t.pump();
  await t.pump();
  // La fila «Mis pedidos» queda a la vista (en 360×640 está más abajo del primer cuadro).
  final fila = find.byKey(const Key('cuenta_mis_pedidos'));
  await t.ensureVisible(fila);
  await t.pump();
}

/// Cada estado nuevo de #748, con el nombre que lleva en la prueba y en la captura.
final Map<String, MontarEstado748> estados748 = {
  '748 lista mezclada': (t, s, e) => montarMisPedidos(
    t,
    ArnesDePedidos(
      pedidos: PedidosFalsos([
        noSeEnvio748(),
        pedidoDe(id: 'a', numero: 5, fecha: DateTime(2026, 11, 22, 9)),
        pedidoDe(
          id: 'b',
          estado: EstadoDelPedido.rechazado,
          numero: 4,
          motivoRechazo: 'Depositá lo que tenés en mano y pedí de nuevo',
          fecha: DateTime(2026, 11, 20, 9),
        ),
        pedidoDe(
          id: 'c',
          estado: EstadoDelPedido.recibido,
          numero: 3,
          fecha: DateTime(2026, 11, 10, 9),
        ),
      ]),
    ),
    tamano: s,
    escala: e,
  ),
  '748 lista solo rechazado': (t, s, e) => montarMisPedidos(
    t,
    ArnesDePedidos(pedidos: PedidosFalsos([noSeEnvio748()])),
    tamano: s,
    escala: e,
  ),
  '748 filtro por autorizar con rechazado': (t, s, e) async {
    await montarMisPedidos(
      t,
      ArnesDePedidos(pedidos: PedidosFalsos([noSeEnvio748()])),
      tamano: s,
      escala: e,
    );
    await tocar(t, find.byKey(const Key('pedidos_filtro_porAutorizar')));
  },
  '748 detalle fecha fuera de campaña': (t, s, e) => montarDetalle(
    t,
    ArnesDePedidos(pedidos: PedidosFalsos([noSeEnvio748()])),
    'ped-1',
    tamano: s,
    escala: e,
  ),
  '748 detalle otra causa': (t, s, e) => montarDetalle(
    t,
    ArnesDePedidos(pedidos: PedidosFalsos([noSeEnvio748(causa: CausaDelRechazoAlEnviar.otra)])),
    'ped-1',
    tamano: s,
    escala: e,
  ),
  '748 detalle monto largo y diez líneas': (t, s, e) => montarDetalle(
    t,
    ArnesDePedidos(
      pedidos: PedidosFalsos([
        noSeEnvio748(
          montoCentavos: 987654321,
          lineas: [
            for (var i = 0; i < 10; i++)
              LineaDelPedido(
                id: 'l$i',
                productoId: i < 3 ? ['p-salud', 'p-hijos', 'p-vida'][i] : 'p-extra-$i',
                cantidad: 100 + i,
              ),
          ],
        ),
      ]),
    ),
    'ped-1',
    tamano: s,
    escala: e,
  ),
  '748 Mi Cuenta con uno que no se envió': (t, s, e) => _cuenta(t, [noSeEnvio748()], s, e),
  '748 Mi Cuenta con por autorizar y no enviados': (t, s, e) => _cuenta(
    t,
    [
      pedidoDe(id: 'a'),
      pedidoDe(id: 'b'),
      noSeEnvio748(id: 'c'),
      noSeEnvio748(id: 'd'),
      noSeEnvio748(id: 'e'),
    ],
    s,
    e,
  ),
  '748 Mi Cuenta con doce que no se enviaron': (t, s, e) =>
      _cuenta(t, [pedidoDe(id: 'a'), for (var i = 0; i < 12; i++) noSeEnvio748(id: 'n$i')], s, e),
};
