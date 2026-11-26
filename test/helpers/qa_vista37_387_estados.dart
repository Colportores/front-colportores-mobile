// Los estados de la vista 37 para el QA (#387): cada artboard del canvas y los estados que el canvas no
// dibuja, montados a un tamaño y a una escala de texto dados.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pedidos_arnes.dart';
import 'pedidos_falsos.dart';

typedef MontarEstado37 = Future<void> Function(WidgetTester tester, Size tamano, double escala);

Finder get _botonEnviar => find.byKey(const Key('pedidos_boton_principal'));

PedidosFalsos _pedidosDelCanvas() => PedidosFalsos([
  pedidoDe(id: 'hoy', fecha: ahoraLocal.subtract(const Duration(minutes: 30))),
  pedidoDe(
    id: 'desp',
    estado: EstadoDelPedido.despachado,
    fecha: DateTime(2026, 10, 15, 12),
    montoCentavos: 480000,
    numero: 7,
    lineas: [const LineaDelPedido(id: 'd1', productoId: 'p-vida', cantidad: 40)],
  ),
  pedidoDe(
    id: 'rec',
    estado: EstadoDelPedido.recibido,
    fecha: DateTime(2026, 10, 2, 12),
    montoCentavos: 3740000,
    numero: 5,
  ),
]);

final estados37 = <String, MontarEstado37>{
  '37A·01 armar': (t, s, e) async {
    await montarPedir(t, ArnesDePedidos(), tamano: s, escala: e);
    await sumar(t, 'p-salud', 4);
    await sumar(t, 'p-hijos', 2);
  },
  '37A·08 revistas': (t, s, e) async {
    await montarPedir(t, ArnesDePedidos(), tamano: s, escala: e);
    await tocar(t, find.byKey(const Key('pedido_chip_revistas')));
    await sumar(t, 'p-vida', 3);
  },
  '37A·02 supera el límite': (t, s, e) async {
    await montarPedir(t, ArnesDePedidos(limitePesos: 30000), tamano: s, escala: e);
    await sumar(t, 'p-salud', 8);
    await sumar(t, 'p-hijos', 4);
  },
  '37A·03 vacío': (t, s, e) => montarPedir(t, ArnesDePedidos(), tamano: s, escala: e),
  '37A·04 enviando': (t, s, e) async {
    final arnes = ArnesDePedidos()..pedidos.esperaAlEnviar = Completer<void>();
    await montarPedir(t, arnes, tamano: s, escala: e);
    await sumar(t, 'p-salud', 1);
    await tocar(t, _botonEnviar, cuadros: 2);
  },
  '37A·05 enviado': (t, s, e) async {
    await montarPedir(t, ArnesDePedidos(), tamano: s, escala: e);
    await sumar(t, 'p-salud', 4);
    await tocar(t, _botonEnviar, cuadros: 4);
    await t.pump();
  },
  '37A·05 enviado sin conexión': (t, s, e) async {
    await montarPedir(
      t,
      ArnesDePedidos(),
      tamano: s,
      escala: e,
      conexion: TipoConexion.sinConexion,
    );
    await sumar(t, 'p-salud', 4);
    await tocar(t, _botonEnviar, cuadros: 4);
    await t.pump();
  },
  '37A·06 sin conexión': (t, s, e) async {
    await montarPedir(
      t,
      ArnesDePedidos(),
      tamano: s,
      escala: e,
      conexion: TipoConexion.sinConexion,
    );
    await sumar(t, 'p-salud', 1);
  },
  '37A·07 error': (t, s, e) async {
    final arnes = ArnesDePedidos();
    arnes.pedidos.fallasAlEnviar.add(const FailurePedidoNoGuardado(causa: 'X'));
    await montarPedir(t, arnes, tamano: s, escala: e);
    await sumar(t, 'p-salud', 3);
    await tocar(t, _botonEnviar, cuadros: 4);
    await t.pump();
  },
  '37A sin catálogo': (t, s, e) => montarPedir(
    t,
    ArnesDePedidos(armado: ArmadoFalso(productos: const [])),
    tamano: s,
    escala: e,
  ),
  '37A error de productos': (t, s, e) => montarPedir(
    t,
    ArnesDePedidos(armado: ArmadoFalso(fallaProductos: true)),
    tamano: s,
    escala: e,
  ),
  '37B·01 mis pedidos': (t, s, e) => montarMisPedidos(
    t,
    ArnesDePedidos(pedidos: _pedidosDelCanvas()),
    tamano: s,
    escala: e,
  ),
  '37B·01 filtro sin pedidos': (t, s, e) async {
    await montarMisPedidos(
      t,
      ArnesDePedidos(pedidos: _pedidosDelCanvas()),
      tamano: s,
      escala: e,
    );
    await tocar(t, find.byKey(const Key('pedidos_filtro_porAutorizar')));
    await tocar(t, find.byKey(const Key('pedidos_filtro_recibidos')));
    await tocar(t, find.byKey(const Key('pedidos_filtro_porAutorizar')));
  },
  '37B·04 sin pedidos': (t, s, e) => montarMisPedidos(t, ArnesDePedidos(), tamano: s, escala: e),
  '37B·05 cargando': (t, s, e) {
    final arnes = ArnesDePedidos(pedidos: _pedidosDelCanvas())
      ..pedidos.esperaLectura = Completer<void>();
    return montarMisPedidos(t, arnes, tamano: s, escala: e);
  },
  '37B·06 error': (t, s, e) {
    final arnes = ArnesDePedidos(pedidos: _pedidosDelCanvas())..pedidos.fallaAlLeer = true;
    return montarMisPedidos(t, arnes, tamano: s, escala: e);
  },
  '37B·02 detalle por autorizar (pasó el límite)': (t, s, e) => montarDetalle(
    t,
    ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(excedeLimite: true)])),
    'ped-1',
    tamano: s,
    escala: e,
  ),
  '37B·02 cancelar: confirmación': (t, s, e) async {
    await montarDetalle(
      t,
      ArnesDePedidos(pedidos: _pedidosDelCanvas()),
      'hoy',
      tamano: s,
      escala: e,
    );
    await tocar(t, find.byKey(const Key('pedidos_boton_secundario')));
  },
  '37B·02 cancelar: falla': (t, s, e) async {
    final arnes = ArnesDePedidos(pedidos: _pedidosDelCanvas());
    arnes.pedidos.fallasAlCancelar.add(const FailurePedidoNoCancelado(causa: 'X'));
    await montarDetalle(t, arnes, 'hoy', tamano: s, escala: e);
    await tocar(t, find.byKey(const Key('pedidos_boton_secundario')));
    await tocar(t, find.byKey(const Key('pedido_si_cancelar')), cuadros: 4);
  },
  '37B·03 no autorizado': (t, s, e) => montarDetalle(
    t,
    ArnesDePedidos(
      pedidos: PedidosFalsos([
        pedidoDe(
          estado: EstadoDelPedido.rechazado,
          fecha: DateTime(2026, 10, 20, 12),
          montoCentavos: 2196000,
          motivoRechazo: 'Depositá lo que tenés en mano y pedí de nuevo',
          numero: 9,
        ),
      ]),
    ),
    'ped-1',
    tamano: s,
    escala: e,
  ),
  'detalle cancelado': (t, s, e) => montarDetalle(
    t,
    ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(estado: EstadoDelPedido.cancelado)])),
    'ped-1',
    tamano: s,
    escala: e,
  ),
  'detalle autorizado con una línea reducida': (t, s, e) => montarDetalle(
    t,
    ArnesDePedidos(
      pedidos: PedidosFalsos([
        pedidoDe(
          estado: EstadoDelPedido.autorizado,
          numero: 3,
          montoAutorizadoCentavos: 900000,
          lineas: [
            const LineaDelPedido(
              id: 'a1',
              productoId: 'p-salud',
              cantidad: 4,
              cantidadAutorizada: 2,
            ),
            const LineaDelPedido(id: 'a2', productoId: 'p-hijos', cantidad: 2),
          ],
        ),
      ]),
    ),
    'ped-1',
    tamano: s,
    escala: e,
  ),
  'detalle no encontrado': (t, s, e) =>
      montarDetalle(t, ArnesDePedidos(), 'no-esta', tamano: s, escala: e),
};
