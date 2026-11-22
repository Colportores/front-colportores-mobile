// QA del PR #351 (#313 y #318, vista 14): cada estado de la vista, los de este PR incluidos, en los
// dos teléfonos del checklist (360×640 y 412×915) con el texto al 100 %, 200 % y 300 %: sin
// desborde, con todo el texto dentro del ancho y con la acción de salida a mano y del tamaño de
// toque. Después, las guías de accesibilidad de Flutter (toque de Android e iOS, etiquetas) al 100 %
// y al 200 %, y el contraste del texto en el tamaño de las guías (390×844).
//
// Los artboards del diseño son A01 a A06 de la vista 14; A05 con la sesión abierta, el reenvío en
// vuelo, el aviso de lectura lenta y la espera vigente son los estados que el diseño no dibuja.
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista14_351_arnes.dart';

void main() {
  group('QA #351 · cada estado sin desborde, con la salida a mano', () {
    for (final estado in estadosQa) {
      for (final tam in tamanosQa) {
        for (final texto in textosQa) {
          testWidgets(
            '${estado.nombre} en ${nombreTamQa(tam)} con el texto al ${(texto * 100).toInt()} %',
            (tester) async {
              await estado.armar(tester, tam, texto);

              expect(tester.takeException(), isNull, reason: 'sin overflow ni errores de pintado');
              expect(find.text(estado.visible), findsOneWidget, reason: estado.nombre);
              expect(find.byType(RecuperacionPasswordPage), findsOneWidget);

              // Todo el texto dentro del ancho de la pantalla (un renglón cortado por el costado).
              for (var i = 0; i < find.byType(Text).evaluate().length; i++) {
                final r = tester.getRect(find.byType(Text).at(i));
                expect(
                  r.left,
                  greaterThanOrEqualTo(-0.5),
                  reason: 'texto $i fuera por la izquierda',
                );
                expect(
                  r.right,
                  lessThanOrEqualTo(tam.width + 0.5),
                  reason: 'texto $i fuera por la derecha',
                );
              }

              // La acción de salida se alcanza deslizando y tiene el tamaño de toque.
              await tester.ensureVisible(estado.accion);
              await tester.pump();
              final r = tester.getRect(estado.accion);
              expect(r.top, greaterThanOrEqualTo(-0.5));
              expect(r.bottom, lessThanOrEqualTo(tam.height + 0.5));
              expect(r.height, greaterThanOrEqualTo(48));
              expect(r.width, greaterThanOrEqualTo(48));
              expect(habilitadoQa(tester, estado.accion), estado.habilitada);
            },
          );
        }
      }
    }
  });

  group('QA #351 · guías de accesibilidad de Flutter en cada estado', () {
    for (final estado in estadosQa) {
      for (final tam in tamanosQa) {
        for (final texto in const [1.0, 2.0]) {
          testWidgets(
            '${estado.nombre} en ${nombreTamQa(tam)} con el texto al ${(texto * 100).toInt()} %: toque y etiquetas',
            (tester) async {
              final handle = tester.ensureSemantics();
              await estado.armar(tester, tam, texto);

              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              handle.dispose();
            },
          );
        }
      }
    }

    // El contraste solo se mide bien en la pantalla de las guías (390×844, 1 px lógico = 1 físico).
    for (final estado in estadosQa) {
      testWidgets('${estado.nombre} en 390×844: contraste del texto', (tester) async {
        final handle = tester.ensureSemantics();
        await estado.armar(tester, const Size(390, 844), 1);
        await tester.pump(const Duration(milliseconds: 500));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
