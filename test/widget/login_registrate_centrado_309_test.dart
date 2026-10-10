// «¿No tenés cuenta? Registrate» del login con el texto al 200 % (#309, QA del PR #341): se parte en
// renglones y van centrados, como el resto de la pantalla. Va en su propio archivo porque carga la
// letra real (Inter) y `FontLoader` vale para todo el archivo: mezclada con las pruebas de la letra de
// `flutter_test` les cambiaría las medidas.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_login_enlace_309_arnes.dart';

void main() {
  // Con texto al 200 % «¿No tenés cuenta? Registrate» se parte en renglones: van centrados, como el
  // resto de la pantalla (QA de #309). Letra real; cada renglón se mide sin el espacio con que
  // termina (el espacio que cuelga al final del primero entra en la caja pero no se pinta).
  testWidgets('«Registrate» a 412x915 con texto ×2: cada renglón del texto queda centrado', (
    tester,
  ) async {
    fijarPantallaLogin(tester, const Size(412, 915), texto: 2);
    await llegarALogin(tester, PantallaLogin.inicial, fuentesReales: true);
    await tester.ensureVisible(find.byKey(llaveRegistro));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.descendant(of: find.byKey(llaveRegistro), matching: find.byType(Text)))
          .textAlign,
      TextAlign.center,
    );
    final render = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(llaveRegistro), matching: find.byType(RichText)).first,
    );
    final texto = render.text.toPlainText();
    // Letra por letra (sin los espacios) y agrupadas por renglón: así el espacio con que termina el
    // primero no cuenta.
    final porRenglon = <int, List<TextBox>>{};
    for (var i = 0; i < texto.length; i++) {
      if (texto[i] == ' ') continue;
      final cajas = render.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      porRenglon.putIfAbsent(cajas.first.top.round(), () => []).add(cajas.first);
    }
    expect(porRenglon.length, greaterThanOrEqualTo(2), reason: 'se esperaba un texto partido');
    final centroPantalla = tester.view.physicalSize.width / 2;
    for (final cajas in porRenglon.values) {
      final izquierda = cajas.map((c) => c.left).reduce(math.min);
      final derecha = cajas.map((c) => c.right).reduce(math.max);
      final centro = render.localToGlobal(Offset((izquierda + derecha) / 2, 0)).dx;
      expect(centro, closeTo(centroPantalla, 1), reason: 'renglón de $izquierda a $derecha');
    }
  });
}
