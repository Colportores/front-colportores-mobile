// QA de «Mapas offline» (vista 35, HU-SYNC-010, #132): cada artboard a textScaler 2.0 en los dos
// teléfonos de la matriz, sin desbordes, con las fuentes reales del proyecto (con la de prueba cada
// letra ocupa un cuadrado y los desbordes salen falsos). Con `QA_CAPTURAS=1` además saca capturas PNG
// a `.dart_tool/qa_capturas/` (gitignored: nunca se commitean).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_mapas_offline_132_arnes.dart';

void main() {
  for (final tamano in [qaChico, qaGrande]) {
    final t = '${tamano.width.toInt()}x${tamano.height.toInt()}';
    group('QA #132 · textScaler 2.0 a $t', () {
      for (final estado in QaEstado.values) {
        testWidgets('${estado.name}: sin desbordes ni texto cortado', (tester) async {
          await qaLlegar(tester, estado, tamano: tamano, escala: 2, fuentes: true);
          expect(tester.takeException(), isNull);
          final listas = find.byType(ListView);
          if (listas.evaluate().isNotEmpty) {
            await tester.drag(listas.first, const Offset(0, -3000));
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
        });
      }

      testWidgets('35-10: la hoja de la sugerencia no desborda', (tester) async {
        await qaCargarFuentes(tester);
        await qaMontarSugerencia(tester, tamano: tamano, escala: 2);
        expect(find.byKey(const Key('sugerencia_mapa_hoja')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  if (qaCapturas) {
    group('QA #132 · capturas', () {
      for (final estado in QaEstado.values) {
        for (final (nombre, tamano, escala) in [
          ('chico', qaChico, 1.0),
          ('grande', qaGrande, 1.0),
          ('chico_x2', qaChico, 2.0),
        ]) {
          testWidgets('${estado.name} $nombre', (tester) async {
            await qaCargarFuentes(tester);
            await qaLlegar(tester, estado, tamano: tamano, escala: escala, fuentes: true);
            await qaCapturar(tester, '${estado.name}_$nombre');
          });
        }
      }
      for (final (nombre, tamano, escala) in [
        ('chico', qaChico, 1.0),
        ('grande', qaGrande, 1.0),
        ('chico_x2', qaChico, 2.0),
      ]) {
        testWidgets('e10 $nombre', (tester) async {
          await qaCargarFuentes(tester);
          await qaMontarSugerencia(tester, tamano: tamano, escala: escala);
          await qaCapturar(tester, 'e10_$nombre');
        });
      }
    });
  }
}
