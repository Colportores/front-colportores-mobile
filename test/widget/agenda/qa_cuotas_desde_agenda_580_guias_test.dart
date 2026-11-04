// Guías de accesibilidad de Flutter sobre el detalle de una cuota (con «Ver las cuotas») y sobre las
// cuotas abiertas desde el aviso (#580), en 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto
// del QA: la guía de contraste lee los colores de la captura y con las fuentes reales da falsos
// negativos.
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_cuotas_desde_agenda_580_arnes.dart';

String _suf(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

void main() {
  sinFuentesReales580();

  for (final tamano in [chico580, grande580]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado580.values) {
        group('${estado.rotulo} · ${_suf(tamano, escala)}', () {
          Future<void> verificar(
            WidgetTester tester,
            String nombre,
            AccessibilityGuideline guia,
          ) async {
            final h = tester.ensureSemantics();
            await llegarA580(tester, estado, tamano: tamano, escala: escala);
            if (estado.conAcceso) {
              await tester.ensureVisible(botonCuotas580);
              await tester.pump();
            }
            await expectLater(tester, meetsGuideline(guia), reason: nombre);
            h.dispose();
          }

          testWidgets('tamaño de toque Android (48 dp)', (tester) async {
            await verificar(tester, 'android', androidTapTargetGuideline);
          });
          testWidgets('tamaño de toque iOS (44 pt)', (tester) async {
            await verificar(tester, 'ios', iOSTapTargetGuideline);
          });
          testWidgets('todo lo tocable tiene nombre', (tester) async {
            await verificar(tester, 'nombre', labeledTapTargetGuideline);
          });
          testWidgets('contraste del texto', (tester) async {
            await verificar(tester, 'contraste', textContrastGuideline);
          });
        });
      }
    }
  }

  group('Las cuotas abiertas desde el aviso', () {
    for (final tamano in [chico580, grande580]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('guías sobre 30A-06 · ${_suf(tamano, escala)}', (tester) async {
          final h = tester.ensureSemantics();
          final app = await abrirApp580(
            tester,
            tamano: tamano,
            escala: escala,
            reloj: despuesDeLaCuota2,
          );
          app.recordatorios.tocar('ag-1');
          await asentar580(tester);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      }
    }
  });
}
