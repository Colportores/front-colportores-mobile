// Mi Cuenta con los pedidos (33A·01, HU-STK-009, #387): «+ Hacer un pedido» en ACCIONES y el enlace «Mis
// pedidos · N por autorizar ›».
import 'package:colportores_mobile/features/pedidos/domain/entities/pedido.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart' show montarCuenta;
import '../../helpers/pedidos_arnes.dart';
import '../../helpers/pedidos_falsos.dart';

Finder _t(String texto) => find.text(texto, findRichText: true);

Future<ArnesDePedidos> _montar(WidgetTester tester, {List<Pedido> pedidos = const []}) async {
  final arnes = ArnesDePedidos(pedidos: PedidosFalsos(pedidos));
  await montarCuenta(tester, arnes.cuenta, overrides: arnes.overrides(conCuenta: false));
  await tester.pump();
  await tester.pump();
  return arnes;
}

void main() {
  testWidgets('dado que no pedí nada, «Mis pedidos» no inventa un cero', (tester) async {
    await _montar(tester);
    expect(_t('Mis pedidos'), findsOneWidget);
    expect(find.textContaining('por autorizar'), findsNothing);
  });

  testWidgets('dado un pedido por autorizar, el enlace lo cuenta; los ya decididos no cuentan', (
    tester,
  ) async {
    await _montar(
      tester,
      pedidos: [
        pedidoDe(id: 'a', numero: 1),
        pedidoDe(id: 'b', estado: EstadoDelPedido.autorizado, numero: 2),
      ],
    );
    expect(_t('1 por autorizar'), findsOneWidget);
  });

  testWidgets('dados varios por autorizar, dice cuántos', (tester) async {
    await _montar(
      tester,
      pedidos: [
        pedidoDe(id: 'a'),
        pedidoDe(id: 'b'),
      ],
    );
    expect(_t('2 por autorizar'), findsOneWidget);
  });

  testWidgets('el enlace lo lee el lector de pantalla con su cuenta', (tester) async {
    final manejador = tester.ensureSemantics();
    await _montar(tester, pedidos: [pedidoDe(id: 'a')]);
    expect(
      tester.getSemantics(find.byKey(const Key('cuenta_mis_pedidos'))).label,
      'Mis pedidos, 1 por autorizar',
    );
    manejador.dispose();
  });

  testWidgets('«Mis pedidos» abre la lista, y atrás vuelve a Mi Cuenta', (tester) async {
    await _montar(tester, pedidos: [pedidoDe(id: 'a', numero: 1)]);
    await tocar(tester, find.byKey(const Key('cuenta_mis_pedidos')), cuadros: 8);
    expect(find.byKey(const Key('pedidos_lista')), findsOneWidget);
    expect(find.byKey(const Key('pedido_a')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cuenta_pestana')), findsOneWidget);
  });

  testWidgets('«+ Hacer un pedido» abre «Nuevo pedido» (un solo toque aunque se toque dos veces)', (
    tester,
  ) async {
    await _montar(tester);
    await tester.ensureVisible(find.byKey(const Key('cuenta_hacer_un_pedido')));
    await tester.tap(find.byKey(const Key('cuenta_hacer_un_pedido')));
    await tester.tap(find.byKey(const Key('cuenta_hacer_un_pedido')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_t('Nuevo pedido'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('cuenta_pestana')),
      findsOneWidget,
      reason: 'una sola pantalla encima',
    );
  });

  testWidgets('con el texto al 200 % las dos acciones y el enlace no desbordan', (tester) async {
    final arnes = ArnesDePedidos(pedidos: PedidosFalsos([pedidoDe(id: 'a')]));
    await montarCuenta(
      tester,
      arnes.cuenta,
      tamano: const Size(320, 568),
      escala: 2,
      overrides: arnes.overrides(conCuenta: false),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('+ Hacer un pedido', skipOffstage: false), findsOneWidget);
  });
}
