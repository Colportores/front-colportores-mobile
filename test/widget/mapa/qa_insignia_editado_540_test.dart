// QA de #540 (PR #557), vista 03 «Alta de ubicación» (HU-UBI-001, QA #288): la insignia «Editado» de la
// columna NÚMERO no se parte con el texto grande. El test que se destapó en `alta_ubicacion_qa_ronda2_test.dart`
// vuelve a maquetar el texto con el ancho que ya tiene adentro del `FittedBox` y con `softWrap: false`:
// pasaría siempre. Acá se mide lo que ve la persona, con las fuentes reales: una sola línea, entera dentro
// de la columna del número y, si el `FittedBox` la achica, que la letra no quede más chica que con texto 1×.
import 'package:colportores_mobile/features/mapa/presentation/widgets/campos_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart';

const _letra = 10.5; // `InsigniaCampo`: el texto va a 10,5 sp antes de la escala del sistema.

void main() {
  for (final (tamano, escala) in <(Size, double)>[
    (const Size(360, 640), 1.0),
    (const Size(360, 640), 1.8),
    (const Size(360, 640), 2.0),
    (const Size(320, 568), 1.0),
    (const Size(320, 568), 1.8),
    (const Size(320, 568), 2.0),
    (const Size(412, 915), 2.0),
  ]) {
    testWidgets(
      '${tamano.width.round()}×${tamano.height.round()} · texto $escala×: «Editado» en una línea, '
      'entera y sin quedar más chica que a 1×',
      (tester) async {
        await cargarFuentesReales();
        await montarAlta(tester, tamano: tamano, escala: escala);
        await tester.enterText(find.widgetWithText(TextField, '1234'), '1236');
        await asentar(tester);
        await tester.pumpAndSettle();

        final etiqueta = find.text('Editado');
        expect(etiqueta, findsOneWidget);
        final insignia = find.ancestor(of: etiqueta, matching: find.byType(InsigniaCampo));
        final caja = find.descendant(of: insignia, matching: find.byType(FittedBox)).first;
        final contenido = find.descendant(of: caja, matching: find.byType(Container)).first;

        // Una sola línea: la altura del texto es la de un renglón de la letra escalada.
        final alto = tester.getSize(etiqueta).height;
        expect(
          alto,
          lessThan(_letra * escala * 1.6),
          reason: '«Editado» pasó a 2 renglones ($alto dp)',
        );

        // Cuánto la achica el FittedBox.
        final achicada = tester.getSize(caja).width / tester.getSize(contenido).width;
        final letraEfectiva = _letra * escala * achicada;
        expect(
          letraEfectiva,
          greaterThanOrEqualTo(_letra - 0.01),
          reason:
              '«Editado» se ve a ${letraEfectiva.toStringAsFixed(1)} sp (escala del FittedBox '
              '${achicada.toStringAsFixed(2)}), menos que los $_letra sp de texto 1×',
        );

        // Entera dentro de la columna del número.
        final columna = tester.getRect(find.widgetWithText(TextField, '1236'));
        final rotulo = tester.getRect(caja);
        expect(rotulo.left, greaterThanOrEqualTo(columna.left - 0.5));
        expect(
          rotulo.right,
          lessThanOrEqualTo(columna.right + 0.5),
          reason: '«Editado» se sale de la columna',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
