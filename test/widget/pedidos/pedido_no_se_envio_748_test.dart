// El pedido que el servidor rechazó al sincronizar (vista 37B, HU-STK-009, #748; decisión del 23/11, P5): en
// «Mis pedidos», en el detalle y en Mi Cuenta se ve «No se envió» con la causa y qué hacer. El canvas 37 no
// dibuja este estado: sale del issue y reusa las piezas de «No autorizado» (37B·03).

import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:colportores_mobile/features/pedidos/presentation/textos_pedidos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart' show montarCuenta;
import '../../helpers/pedidos_arnes.dart';
import '../../helpers/pedidos_falsos.dart';

Finder _t(String texto) => find.text(texto, findRichText: true);

const _porLaFecha =
    'Tu pedido no se envió: la fecha queda fuera de tu campaña. Armalo de nuevo o hablá con tu '
    'coordinador.';
const _otra =
    'Tu pedido no se envió: el servidor no lo aceptó. Armalo de nuevo o hablá con tu coordinador.';

Pedido _noSeEnvio({
  String id = 'ped-1',
  CausaDelRechazoAlEnviar causa = CausaDelRechazoAlEnviar.fueraDeLaCampania,
  DateTime? fecha,
}) => pedidoDe(
  id: id,
  estado: EstadoDelPedido.noSeEnvio,
  rechazoAlEnviar: causa,
  fecha: fecha ?? DateTime(2026, 11, 23, 9, 30),
);

void main() {
  group('Mis pedidos', () {
    testWidgets(
      'dado un pedido que el servidor rechazó, la tarjeta dice «No se envió» y no «Por autorizar»',
      (tester) async {
        final manejador = tester.ensureSemantics();
        await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])));
        expect(_t('No se envió'), findsOneWidget);
        expect(_t('Por autorizar'), findsOneWidget, reason: 'solo el chip del filtro');
        expect(
          tester.getSemantics(find.byKey(const Key('pedido_ped-1'))).label,
          startsWith('No se envió, hoy,'),
        );
        manejador.dispose();
      },
    );

    testWidgets(
      'el rechazado está en «Todos» y no en «Por autorizar», «En camino» ni «Recibidos»',
      (tester) async {
        await montarMisPedidos(
          tester,
          ArnesDePedidos(
            pedidos: PedidosFalsos([
              _noSeEnvio(),
              pedidoDe(id: 'ok', numero: 5, fecha: DateTime(2026, 11, 22, 9)),
            ]),
          ),
        );
        expect(find.byKey(const Key('pedido_ped-1')), findsOneWidget);
        for (final filtro in ['porAutorizar', 'enCamino', 'recibidos']) {
          await tocar(tester, find.byKey(Key('pedidos_filtro_$filtro')));
          expect(find.byKey(const Key('pedido_ped-1')), findsNothing, reason: filtro);
        }
        await tocar(tester, find.byKey(const Key('pedidos_filtro_porAutorizar')));
        expect(find.byKey(const Key('pedido_ok')), findsOneWidget);
      },
    );

    testWidgets('tocar la tarjeta abre el detalle, y volver y reentrar lo muestra igual', (
      tester,
    ) async {
      await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])));
      for (var vuelta = 0; vuelta < 2; vuelta++) {
        await tocar(tester, find.byKey(const Key('pedido_ped-1')), cuadros: 8);
        expect(_t(_porLaFecha), findsOneWidget, reason: 'vuelta $vuelta');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pedido_ped-1')), findsOneWidget, reason: 'vuelta $vuelta');
      }
    });

    testWidgets('dos toques seguidos a la tarjeta abren un solo detalle', (tester) async {
      await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])));
      final tarjeta = find.byKey(const Key('pedido_ped-1'));
      await tester.tap(tarjeta);
      await tester.tap(tarjeta, warnIfMissed: false);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('pedido_detalle')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pedido_detalle')), findsNothing, reason: 'no quedó otro debajo');
    });
  });

  group('Detalle', () {
    testWidgets(
      'dado el alta rechazada por la fecha, veo «No se envió», la causa, qué hacer y «Armar uno nuevo»; '
      'sin «Cancelar pedido»',
      (tester) async {
        await montarDetalle(
          tester,
          ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])),
          'ped-1',
        );
        expect(_t('PEDIDO DE HOY'), findsOneWidget);
        expect(_t('No se envió'), findsOneWidget);
        expect(_t(_porLaFecha), findsOneWidget);
        expect(find.text('Cancelar pedido'), findsNothing);
        // Las líneas siguen a la vista: no se borró nada.
        expect(find.byKey(const Key('pedido_linea_p-salud')), findsOneWidget);
        expect(_t('Armar uno nuevo'), findsOneWidget);
      },
    );

    testWidgets('dada otra causa, el aviso no afirma por qué y dice qué hacer', (tester) async {
      await montarDetalle(
        tester,
        ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio(causa: CausaDelRechazoAlEnviar.otra)])),
        'ped-1',
      );
      expect(_t(_otra), findsOneWidget);
      expect(find.textContaining('fuera de tu campaña'), findsNothing);
    });

    testWidgets('«Armar uno nuevo» abre «Nuevo pedido»', (tester) async {
      await montarDetalle(tester, ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])), 'ped-1');
      await tocar(tester, find.text('Armar uno nuevo'), cuadros: 8);
      expect(_t('Nuevo pedido'), findsOneWidget);
    });

    testWidgets('el aviso se lee como aviso en vivo y el botón está al alcance del dedo', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montarDetalle(tester, ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])), 'ped-1');
      final aviso = tester.getSemantics(
        find.ancestor(of: _t(_porLaFecha), matching: find.byType(Semantics)).first,
      );
      expect(aviso.label, contains('la fecha queda fuera de tu campaña'));
      final boton = tester.getSize(find.byKey(const Key('pedidos_boton_principal')));
      expect(boton.height, greaterThanOrEqualTo(48));
      manejador.dispose();
    });

    testWidgets(
      'dado que el rechazo llega con el detalle abierto, pasa de «Por autorizar» a «No se envió»; y si '
      'la cola lo reintenta, vuelve',
      (tester) async {
        final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe()]));
        await montarDetalle(tester, arnes, 'ped-1');
        expect(find.text('Cancelar pedido'), findsOneWidget);
        expect(find.textContaining('no se envió'), findsNothing);

        arnes.pedidos.pedidos[0] = _noSeEnvio(fecha: ahoraPedidos);
        arnes.pedidos.cambiar();
        await tester.pump();
        await tester.pump();
        expect(_t(_porLaFecha), findsOneWidget);
        expect(find.text('Cancelar pedido'), findsNothing);

        arnes.pedidos.pedidos[0] = pedidoDe();
        arnes.pedidos.cambiar();
        await tester.pump();
        await tester.pump();
        expect(find.text('Cancelar pedido'), findsOneWidget);
        expect(find.textContaining('no se envió'), findsNothing);
      },
    );

    testWidgets('dos toques seguidos a «Armar uno nuevo» abren una sola pantalla', (tester) async {
      await montarDetalle(tester, ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])), 'ped-1');
      final boton = find.text('Armar uno nuevo');
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_t('Nuevo pedido'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_t('Nuevo pedido'), findsNothing, reason: 'no quedó otra encima');
      expect(_t(_porLaFecha), findsOneWidget);
    });
  });

  group('Mi Cuenta', () {
    Future<void> montar(WidgetTester tester, List<Pedido> pedidos) async {
      final arnes = ArnesDePedidos(pedidos: PedidosFalsos(pedidos));
      await montarCuenta(tester, arnes.cuenta, overrides: arnes.overrides(conCuenta: false));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('con uno que no se envió, el enlace lo dice y no lo cuenta como «por autorizar»', (
      tester,
    ) async {
      await montar(tester, [_noSeEnvio()]);
      expect(_t('1 no se envió'), findsOneWidget);
      expect(find.textContaining('por autorizar'), findsNothing);
    });

    testWidgets('con uno por autorizar y dos que no se enviaron, dice las dos cosas', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montar(tester, [
        pedidoDe(id: 'a', numero: 1),
        _noSeEnvio(id: 'b'),
        _noSeEnvio(id: 'c', causa: CausaDelRechazoAlEnviar.otra),
      ]);
      expect(_t('1 por autorizar · 2 no se enviaron'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('cuenta_mis_pedidos'))).label,
        'Mis pedidos, 1 por autorizar · 2 no se enviaron',
      );
      manejador.dispose();
    });
  });

  group('Datos límite', () {
    for (final (nombre, tamano) in [
      ('360×640', const Size(360, 640)),
      ('320×568', const Size(320, 568)),
    ]) {
      testWidgets('con el texto al 200 % a $nombre, la lista y el detalle no desbordan', (
        tester,
      ) async {
        final arnes = ArnesDePedidos(
          pedidos: PedidosFalsos([
            pedidoDe(
              id: 'r',
              estado: EstadoDelPedido.noSeEnvio,
              rechazoAlEnviar: CausaDelRechazoAlEnviar.fueraDeLaCampania,
              montoCentavos: 987654321,
            ),
          ]),
        );
        await montarMisPedidos(tester, arnes, tamano: tamano, escala: 2);
        expect(tester.takeException(), isNull);
        await tocar(tester, find.byKey(const Key('pedido_r')), cuadros: 8);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('fuera de tu campaña', skipOffstage: false), findsOneWidget);
        expect(find.text('Armar uno nuevo', skipOffstage: false), findsOneWidget);
      });
    }

    testWidgets('con una lista larga de pedidos rechazados, se desplaza y todos se pueden abrir', (
      tester,
    ) async {
      final muchos = [
        for (var i = 0; i < 60; i++)
          _noSeEnvio(
            id: 'p$i',
            fecha: DateTime(2026, 9, 1).add(Duration(days: i)),
          ),
      ];
      await montarMisPedidos(tester, ArnesDePedidos(pedidos: PedidosFalsos(muchos)));
      await tester.scrollUntilVisible(
        find.byKey(const Key('pedido_p0')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('pedidos_lista')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(const Key('pedido_p0')), findsOneWidget);
    });

    testWidgets(
      'el texto de la causa es el que da TextosPedidos, sin conexión incluida (se lee de la base)',
      (tester) async {
        expect(TextosPedidos.noSeEnvio(CausaDelRechazoAlEnviar.fueraDeLaCampania), _porLaFecha);
        expect(TextosPedidos.noSeEnvio(CausaDelRechazoAlEnviar.otra), _otra);
        expect(TextosPedidos.noSeEnvio(null), _otra);
        await montarDetalle(
          tester,
          ArnesDePedidos(pedidos: PedidosFalsos([_noSeEnvio()])),
          'ped-1',
        );
        expect(_t(_porLaFecha), findsOneWidget);
      },
    );
  });
}
