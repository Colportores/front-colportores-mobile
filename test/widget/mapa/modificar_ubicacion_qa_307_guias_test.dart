// QA de #307 / PR #321 (vista 07 «Modificar ubicación», HU-UBI-004): guías de accesibilidad de Flutter
// sobre el estado nuevo, el aviso «cambió mientras la editabas» con «Abrir de nuevo» a la vista, en
// los dos teléfonos chicos, texto 1× y 2×, con y sin barra de 3 botones y con el teclado abierto.
//
// Sin las fuentes reales a propósito: `textContrastGuideline` da falsos negativos con ellas (mide el
// contraste sobre el pixel de la captura y con la letra real el antialias baja la nota). La
// geometría con las fuentes reales está en `modificar_ubicacion_qa_307_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/modificar_ubicacion_qa_307_arnes.dart';

void main() {
  final casos = <(String, Size, double, double, bool)>[
    ('360×640 · 1× · sin barra', telefono360x640, 1, 0, false),
    ('360×640 · 2× · barra de 3 botones', telefono360x640, 2, barraDeTresBotones, false),
    ('360×640 · 2× · teclado abierto', telefono360x640, 2, 0, true),
    ('320×568 · 1× · sin barra', telefono320x568, 1, 0, false),
    ('320×568 · 2× · barra de 3 botones', telefono320x568, 2, barraDeTresBotones, false),
  ];

  group('QA #321 · aviso con «Abrir de nuevo»: guías de accesibilidad', () {
    for (final (nombre, tamano, escala, barra, teclado) in casos) {
      testWidgets(nombre, (tester) async {
        final handle = tester.ensureSemantics();
        final m = await abrirEdicion(tester, tamano: tamano, escala: escala, barraInferior: barra);
        await fallarPorCambio(tester, m, conTeclado: teclado);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
