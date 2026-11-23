// QA de #550, vista 16, 16E·01: lo que se ve en la hoja «Esta no es la cuenta de tu respaldo» con las
// fuentes reales (con la de prueba los anchos no valen). Los hallazgos van con `skip`; se activan con
// `--dart-define=QA_HALLAZGOS=true`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista16_550_arnes.dart';

const _qaHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  testWidgets(
    'con la letra al 200 % las tres filas de la hoja quedan alineadas a la izquierda, con la raya '
    'de lado a lado',
    (tester) async {
      await armarEstado550(
        tester,
        Estado550.hoja01,
        ancho: 412,
        alto: 915,
        escala: 2,
        fuentesReales: true,
      );

      // skip: QA #550 — a ≥ 1,3× cada fila es una `Column` centrada: «Último respaldo» queda
      // sangrada y la raya de la 2.ª fila es más corta que las demás.
      final izquierda = [
        'Respaldo anterior',
        'Último respaldo',
        'Cuenta de ahora',
      ].map((t) => tester.getTopLeft(find.text(t)).dx).toSet();
      expect(izquierda, hasLength(1), reason: 'los rótulos arrancan en el mismo borde: $izquierda');
      final anchos = [
        0,
        1,
        2,
      ].map((i) => tester.getSize(find.byKey(Key('drive_otra_cuenta_fila_$i'))).width).toSet();
      expect(anchos, hasLength(1), reason: 'las rayas miden lo mismo: $anchos');
    },
    skip: !_qaHallazgos,
  );

  testWidgets(
    'a 360×640 con letra normal el correo de la cuenta de ahora cabe en un renglón',
    (tester) async {
      await armarEstado550(tester, Estado550.hoja01, ancho: 360, alto: 640, fuentesReales: true);

      // skip: QA #550 — «lu.silva.casa@gmail.com» se parte en «…gmail.co» / «m» (captura
      // 550_hoja04_360x640_1x): el valor es un `Expanded` que parte por letra.
      final correo = tester.getSize(
        find.descendant(
          of: find.byKey(const Key('drive_otra_cuenta_fila_2')),
          matching: find.text('lu.silva.casa@gmail.com'),
        ),
      );
      final rotulo = tester.getSize(find.text('Cuenta de ahora'));
      expect(correo.height, lessThanOrEqualTo(rotulo.height * 1.2), reason: 'un solo renglón');
    },
    skip: !_qaHallazgos,
  );

  testWidgets('a 412×915 con letra normal las tres filas caben en un renglón cada una', (
    tester,
  ) async {
    await armarEstado550(tester, Estado550.hoja01, ancho: 412, alto: 915, fuentesReales: true);

    final rotulo = tester.getSize(find.text('Cuenta de ahora'));
    final correo = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('drive_otra_cuenta_fila_2')),
        matching: find.text('lu.silva.casa@gmail.com'),
      ),
    );
    expect(correo.height, lessThanOrEqualTo(rotulo.height * 1.2));
    expect(tester.takeException(), isNull);
  });
}
