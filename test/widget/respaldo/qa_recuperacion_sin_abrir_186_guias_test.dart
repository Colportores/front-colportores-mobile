// QA #186 (HU-SYNC-006): guías de accesibilidad de Flutter sobre las pantallas 34·07 y 34·08 cuando
// la contraseña abrió solo algunos respaldos (aviso «No pudimos abrir N respaldo(s)…»), en 360x640 y
// 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de contraste lee los colores de la
// captura y con las fuentes reales da falsos negativos.
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_recuperacion_175_arnes.dart';

enum _Variante {
  listoUno('34·08 con 1 sin abrir'),
  listoVarios('34·08 con 12 sin abrir'),
  parcial('34·07 con 2 sin abrir');

  const _Variante(this.rotulo);
  final String rotulo;
}

Future<ArnesRecuperacion> _llegar(
  WidgetTester tester,
  _Variante v,
  Size tamano,
  double escala,
) async {
  final a = ArnesRecuperacion();
  a.servicio.resultado = switch (v) {
    _Variante.listoUno => RecuperacionHecha(informeDePrueba(sinAbrir: 1)),
    _Variante.listoVarios => RecuperacionHecha(informeDePrueba(sinAbrir: 12)),
    _Variante.parcial => RecuperacionHecha(
      informeDePrueba(parcial: true, restauradas: 13, sinAbrir: 2),
    ),
  };
  await abrirAsistente175(tester, a, tamano: tamano, escala: escala);
  await abrirCopia175(tester);
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byKey(const Key('recuperacion_sin_abrir')), findsOneWidget);
  return a;
}

void main() {
  sinFuentesReales175();

  for (final tamano in [chico175, grande175]) {
    for (final escala in [1.0, 2.0]) {
      for (final v in _Variante.values) {
        group('${v.rotulo} · ${sufijo175(tamano, escala)}', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            final a = await _llegar(tester, v, tamano, escala);
            await expectLater(tester, meetsGuideline(guia));
            await liberar175(tester, a);
            h.dispose();
          }

          testWidgets(
            'tamaño de toque Android (48 dp)',
            (t) => verificar(t, androidTapTargetGuideline),
          );
          testWidgets('tamaño de toque iOS (44 pt)', (t) => verificar(t, iOSTapTargetGuideline));
          testWidgets(
            'todo lo tocable tiene nombre',
            (t) => verificar(t, labeledTapTargetGuideline),
          );
          testWidgets('contraste del texto', (t) => verificar(t, textContrastGuideline));
        });
      }
    }
  }
}
