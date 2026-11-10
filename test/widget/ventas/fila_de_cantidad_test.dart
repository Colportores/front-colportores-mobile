// `FilaDeCantidad` (27A·08 y «Lo que dejaste», 42B·08): con la letra grande el − / + baja debajo del
// nombre, así una palabra larga no se parte por la mitad en un teléfono angosto (QA #432,
// «alimentació/n» a 360×640 ×2).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _titulo = 'Consejos sobre salud y alimentación';

void main() {
  var cantidad = 0;

  setUp(() => cantidad = 0);

  Future<void> montar(WidgetTester tester, {required double escala}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => FilaDeCantidad(
                titulo: _titulo,
                cantidad: cantidad,
                alCambiar: (n) => setState(() => cantidad = n),
                etiqueta: TextosVenta.misionero,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('al 100 %, el − / + va al costado del nombre', (tester) async {
    await montar(tester, escala: 1);

    final nombre = tester.getRect(find.text(_titulo));
    final mas = tester.getRect(find.byTooltip('Uno más de $_titulo'));
    expect(mas.left, greaterThan(nombre.right - 1));
    expect(mas.top, lessThan(nombre.bottom));
  });

  testWidgets('al 200 %, el − / + baja debajo del nombre', (tester) async {
    await montar(tester, escala: 2);

    final nombre = tester.getRect(find.text(_titulo));
    final menos = tester.getRect(find.byTooltip('Uno menos de $_titulo'));
    final mas = tester.getRect(find.byTooltip('Uno más de $_titulo'));
    expect(menos.top, greaterThanOrEqualTo(nombre.bottom));
    expect(mas.top, greaterThanOrEqualTo(nombre.bottom));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Uno más de $_titulo'));
    await tester.pump();
    expect(cantidad, 1);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('al 200 %, los botones cumplen las guías de toque y de etiqueta', (tester) async {
    final lector = tester.ensureSemantics();
    await montar(tester, escala: 2);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    lector.dispose();
  });
}
