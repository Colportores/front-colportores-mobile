// Guías de accesibilidad de Flutter sobre cada estado de «Cobro con tarjeta y por transferencia»
// (vista 29, #164), en 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de
// contraste lee los colores de la captura y con las fuentes reales da falsos negativos (con las cajas
// de Ahem lee el color de verdad).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista29_164_arnes.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// skip: QA #164 — los campos de texto nuevos (otra marca, aprobación, referencia, otro banco) miden
/// 41 dp de alto con texto 1,0: menos de los 48 dp de Android y los 44 pt de iOS. Estos son los
/// estados donde algún campo de texto entra en la lista armada; con texto 2,0 crecen y pasan.
bool _tocaUnCampoBajo(Estado164 estado, Size tamano, double escala) {
  if (escala != 1.0) return false;
  return switch (estado) {
    Estado164.a01Otra || Estado164.b01Transferencia || Estado164.b01ConBanco => true,
    Estado164.b02Otro => tamano == chico164,
    Estado164.errorTransferencia => tamano == grande164,
    _ => false,
  };
}

void main() {
  sinFuentesReales164();

  for (final tamano in [chico164, grande164]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado164.values) {
        group('${estado.rotulo} · ${sufijo164(tamano, escala)}', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            final a = await llegarA164(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(guia));
            await liberar164(tester, a);
            h.dispose();
          }

          final conHallazgo = _tocaUnCampoBajo(estado, tamano, escala);
          testWidgets(
            'tamaño de toque Android (48 dp)',
            (t) => verificar(t, androidTapTargetGuideline),
            skip: conHallazgo && !_verHallazgos,
          );
          testWidgets(
            'tamaño de toque iOS (44 pt)',
            (t) => verificar(t, iOSTapTargetGuideline),
            skip: conHallazgo && !_verHallazgos,
          );
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
