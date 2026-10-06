// QA de #286 / PR #288 (vista 03 sobre MapaBase): la pista «Mové el mapa para ajustar el punto» y el
// pin en el mapa chico (360×640) con el texto agrandado, medidos con las fuentes reales.
//
// Los hallazgos de QA quedan con `skip: true` y el motivo en un comentario `// skip: QA #286 …`; el
// implementador les saca el `skip` cuando los arregla.
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart';

/// La pastilla oscura entera de la pista (no solo su texto).
Finder get _pastillaPista =>
    find.ancestor(of: find.text(TextosAlta.mover), matching: find.byType(Container)).first;

void _sinSolape(WidgetTester tester, Finder a, Finder b, String que) {
  final ra = tester.getRect(a);
  final rb = tester.getRect(b);
  expect(ra.overlaps(rb), isFalse, reason: '$que: $ra se pisa con $rb');
}

void main() {
  setUpAll(cargarFuentesReales);

  group('QA #286 · vista 03 A·01 · la pista no tapa el pin en el mapa chico', () {
    testWidgets('a 360×640 y texto 1x la pista no pisa el pin', (tester) async {
      await montarAlta(tester, tamano: const Size(360, 640));
      await tester.pumpAndSettle();

      _sinSolape(tester, _pastillaPista, find.byType(PinAlta), 'pista vs pin');
    });

    testWidgets('a 360×640 y texto 1.3x la pista no pisa el pin', (tester) async {
      await montarAlta(tester, tamano: const Size(360, 640), escala: 1.3);
      await tester.pumpAndSettle();

      _sinSolape(tester, _pastillaPista, find.byType(PinAlta), 'pista vs pin');
    });

    testWidgets(
      'a 360×640 y texto 2x la pista deja margen a los bordes y no pisa el pin',
      (tester) async {
        await montarAlta(tester, tamano: const Size(360, 640), escala: 2);
        await tester.pumpAndSettle();

        final pastilla = tester.getRect(_pastillaPista);
        expect(pastilla.left, greaterThanOrEqualTo(8), reason: 'la pista toca el borde: $pastilla');
        expect(pastilla.right, lessThanOrEqualTo(352), reason: 'la pista toca el borde: $pastilla');
        _sinSolape(tester, _pastillaPista, find.byType(PinAlta), 'pista vs pin');
      },
      // skip: QA #286 — a 360×640 con texto 2x la pista ocupa los 360 dp (2 renglones, sin margen) y tapa la punta del pin y «Volver a mi ubicación».
      skip: true,
    );
  });
}
