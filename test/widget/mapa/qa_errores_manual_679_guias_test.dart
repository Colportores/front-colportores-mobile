// QA de #679: guías de accesibilidad de lo que cambió a la vista, en los dos teléfonos de la matriz.
// Sin fuentes reales a propósito: `textContrastGuideline` con letra real da falsos negativos (lee el
// fondo de una captura con glifos). Los desbordes con letra real van en `qa_errores_manual_679_test`.
//   · «Nueva persona» (32A) con y sin el aviso «¿Descartar lo que escribiste?».
//   · Hoja «¿Cerrar sesión?» con 1 y 3 operaciones pendientes.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'personas_arnes.dart';

const _tamanos = [Size(360, 640), Size(412, 915)];

String _medida(Size t) => '${t.width.toInt()}×${t.height.toInt()}';

Future<void> _guias(WidgetTester tester, {bool contraste = true}) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contraste) await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final tamano in _tamanos) {
    group('guías a ${_medida(tamano)}', () {
      testWidgets('«Nueva persona» con el nombre escrito', (tester) async {
        final handle = tester.ensureSemantics();
        await montarAlta(tester, tamano: tamano);
        await tester.enterText(
          find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
          'Ana',
        );
        await tester.pump();
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('«Nueva persona» con el aviso «¿Descartar lo que escribiste?» abierto', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await montarAlta(tester, tamano: tamano);
        await tester.enterText(
          find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
          'Ana',
        );
        await tester.pump();
        await tester.tap(find.byTooltip('Cerrar'));
        await asentar(tester);
        expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);

        await _guias(tester);
        handle.dispose();
      });

      testWidgets('el aviso se anuncia al lector (diálogo con nombre y su texto)', (tester) async {
        final handle = tester.ensureSemantics();
        await montarAlta(tester, tamano: tamano);
        await tester.enterText(
          find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
          'Ana',
        );
        await tester.pump();
        await tester.tap(find.byTooltip('Cerrar'));
        await asentar(tester);

        expect(find.bySemanticsLabel('¿Descartar lo que escribiste?'), findsWidgets);
        expect(
          tester.getSemantics(find.text('Seguir escribiendo')),
          matchesSemantics(
            label: 'Seguir escribiendo',
            isButton: true,
            hasTapAction: true,
            hasFocusAction: true,
            isEnabled: true,
            hasEnabledState: true,
            isFocusable: true,
          ),
        );
        handle.dispose();
      });

      for (final n in [1, 3]) {
        testWidgets('hoja «¿Cerrar sesión?» con $n pendiente(s)', (tester) async {
          final handle = tester.ensureSemantics();
          tester.view.physicalSize = tamano;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: temaClaro(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        mostrarHojaCerrarSesion(context, pendientes: n, cerrar: () async => true),
                    child: const Text('abrir hoja'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('abrir hoja'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          await _guias(tester);
          handle.dispose();
        });
      }
    });
  }
}
