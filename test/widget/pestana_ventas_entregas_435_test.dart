// HU-VEN-003 (#435): la pestaña Ventas ofrece «Entregas pendientes» (vista 27, 27C·02) junto a
// «Precios», y no ofrece botones mudos si el destino no está.
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _montar(
  WidgetTester tester, {
  VoidCallback? alAbrirEntregas,
  VoidCallback? alAbrirPrecios,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(
        body: PestanaProvisoria(
          pestana: PestanaInicio.ventas,
          alAbrirPrecios: alAbrirPrecios,
          alAbrirEntregas: alAbrirEntregas,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('con destino, ofrece «Entregas pendientes» y lo abre al tocarlo', (tester) async {
    var abiertas = 0;
    await _montar(tester, alAbrirEntregas: () => abiertas++, alAbrirPrecios: () {});

    expect(find.text('Entregas pendientes'), findsOneWidget);
    expect(find.text('Precios'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ventas_entregas')));
    expect(abiertas, 1);
  });

  testWidgets('sin destino no hay botón mudo', (tester) async {
    await _montar(tester);

    expect(find.byKey(const Key('ventas_entregas')), findsNothing);
  });

  testWidgets('al 200 % el botón sigue siendo tocable y nada desborda', (tester) async {
    await _montar(tester, alAbrirEntregas: () {}, alAbrirPrecios: () {}, escala: 2);

    expect(tester.takeException(), isNull);
    final tamano = tester.getSize(find.byKey(const Key('ventas_entregas')));
    expect(tamano.height, greaterThanOrEqualTo(48));
    expect(tamano.width, greaterThanOrEqualTo(48));
  });
}
