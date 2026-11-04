// 27A·14 «Venta registrada: ¿y ahora?». Los grupos ENTREGA y COBRO solo aparecen si sus destinos
// existen (HU-VEN-002 y la vista 28 todavía no): sin ellos la pantalla no ofrece un botón mudo.
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/venta_registrada_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

Future<({List<SeguimientoDeLaVenta> continuo, List<int> termino})> _montar(
  WidgetTester tester, {
  bool conEntrega = true,
  bool conCobro = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final continuo = <SeguimientoDeLaVenta>[];
  final termino = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: VentaRegistradaPage(
        guardada: VentaGuardada(
          venta: ventaDe('v-1', talonario: '0042', monto: 890000),
          items: const [],
        ),
        nombreDelCliente: 'María Fernández',
        conEntrega: conEntrega,
        conCobro: conCobro,
        alContinuar: continuo.add,
        alTerminar: () => termino.add(1),
      ),
    ),
  );
  await asentar(tester);
  return (continuo: continuo, termino: termino);
}

void main() {
  testWidgets('27A·14 dice el talonario, el cliente, el monto y las dos preguntas', (tester) async {
    await _montar(tester);

    expect(find.text('VENTA 0042'), findsOneWidget);
    expect(find.text('Venta registrada'), findsOneWidget);
    expect(find.text(r'María Fernández · $ 8.900'), findsOneWidget);
    expect(find.text('ENTREGA'), findsOneWidget);
    expect(find.text('COBRO'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
    expect(find.text('Terminar sin entregar ni cobrar'), findsOneWidget);
  });

  testWidgets('«Continuar» lleva lo elegido: entregar otro día y cobrar ahora', (tester) async {
    final s = await _montar(tester);

    await tocar(tester, find.text('Entregar otro día'));
    await tocar(tester, find.text('Cobrar ahora'));
    await tocar(tester, find.text('Continuar'));

    expect(s.continuo.single.entrega, MomentoDeEntrega.otroDia);
    expect(s.continuo.single.cobrarAhora, isTrue);
  });

  testWidgets('elegir y desmarcar el cobro lo deja como estaba', (tester) async {
    final s = await _montar(tester);

    await tocar(tester, find.text('Cobrar ahora'));
    await tocar(tester, find.text('Cobrar ahora'));
    await tocar(tester, find.text('Continuar'));

    expect(s.continuo.single.cobrarAhora, isFalse);
    expect(s.continuo.single.entrega, isNull);
  });

  testWidgets('«Terminar sin entregar ni cobrar» cierra sin seguimiento', (tester) async {
    final s = await _montar(tester);

    await tocar(tester, find.byKey(const Key('venta_terminar')));

    expect(s.termino, hasLength(1));
    expect(s.continuo, isEmpty);
  });

  testWidgets('doble toque en «Continuar»: sigue una sola vez', (tester) async {
    final s = await _montar(tester);

    await tester.tap(find.text('Continuar'));
    await tester.tap(find.text('Continuar'), warnIfMissed: false);
    await tester.pump();

    expect(s.continuo, hasLength(1));
  });

  testWidgets('toque en «Terminar» y luego en «Continuar»: gana el primero', (tester) async {
    final s = await _montar(tester);

    await tester.tap(find.byKey(const Key('venta_terminar')));
    await tester.tap(find.text('Continuar'), warnIfMissed: false);
    await tester.pump();

    expect(s.termino, hasLength(1));
    expect(s.continuo, isEmpty);
  });

  testWidgets('sin destinos todavía (entrega y cobro no existen): confirmación con un solo botón', (
    tester,
  ) async {
    final s = await _montar(tester, conEntrega: false, conCobro: false);

    expect(find.text('ENTREGA'), findsNothing);
    expect(find.text('COBRO'), findsNothing);
    expect(find.text('Continuar'), findsNothing);
    expect(find.text('Terminar sin entregar ni cobrar'), findsNothing);
    expect(find.text('Listo'), findsOneWidget);
    expect(find.text('VENTA 0042'), findsOneWidget);
    await tocar(tester, find.text('Listo'));
    expect(s.termino, hasLength(1));
    expect(s.continuo, isEmpty);
  });

  testWidgets('con solo un grupo disponible se ofrece ese y «Continuar»', (tester) async {
    await _montar(tester, conEntrega: false);

    expect(find.text('ENTREGA'), findsNothing);
    expect(find.text('COBRO'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('volver con el gesto no la cierra: la venta ya está guardada y hay que elegir', (
    tester,
  ) async {
    await _montar(tester);

    await tester.binding.handlePopRoute();
    await asentar(tester);

    expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
  });

  for (final escala in [1.0, 2.0]) {
    testWidgets('texto al ${(escala * 100).round()} % en pantalla chica: nada desborda', (
      tester,
    ) async {
      await _montar(tester, escala: escala, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('venta_terminar'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  }
}
