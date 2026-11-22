// QA de #309 (PR #341), alineación con la tipografía real: el canvas (1a, 1b y 17) dibuja el enlace de
// recuperación al ras del borde derecho de los campos y de «Entrar». `qa_login_sin_mantener_sesion_306_test.dart`
// lo mide con la letra de prueba de `flutter_test` (cada letra es un cuadrado del tamaño del texto),
// donde el ancho del texto no es el de un teléfono: acá se carga Inter y se mide lo que se pinta.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_login_enlace_309_arnes.dart';

/// Lo que se pinta del texto del enlace: el borde derecho (en la pantalla) y cuántas líneas ocupa.
({double derecha, double ancho, int lineas, double tamano, int letras}) _textoDelEnlace(
  WidgetTester tester,
) {
  final render = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byKey(llaveRecuperar), matching: find.byType(RichText)).first,
  );
  final texto = render.text.toPlainText();
  final cajas = render.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: texto.length),
  );
  final derecha = cajas.map((c) => c.right).reduce(math.max);
  final lineas = cajas.map((c) => c.top.round()).toSet().length;
  final izquierda = cajas.map((c) => c.left).reduce(math.min);
  return (
    derecha: render.localToGlobal(Offset(derecha, 0)).dx,
    ancho: derecha - izquierda,
    lineas: lineas,
    tamano: render.textScaler.scale(render.text.style?.fontSize ?? 14),
    letras: texto.length,
  );
}

void main() {
  group('Alineación con la tipografía real (canvas 1a, 1b y 17: el enlace al ras del borde)', () {
    for (final pantalla in pantallasConEnlace) {
      for (final (tam, escala) in [
        (const Size(390, 844), 1.0),
        (const Size(360, 640), 1.0),
        (const Size(412, 915), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(412, 915), 2.0),
      ]) {
        testWidgets('${pantalla.nombre} a ${tam.width.toInt()}x${tam.height.toInt()}, texto '
            '×$escala: lo que se pinta del enlace termina en el borde de los campos y de «Entrar» y '
            'ocupa una línea', (tester) async {
          fijarPantallaLogin(tester, tam, texto: escala);
          await llegarALogin(tester, pantalla, fuentesReales: true);
          await tester.ensureVisible(find.byKey(llaveRecuperar));
          await tester.pumpAndSettle();

          final pintado = _textoDelEnlace(tester);
          // Con la letra de prueba cada letra mide lo que el tamaño: si esto falla, no se cargó Inter.
          expect(
            pintado.ancho,
            lessThan(pintado.letras * pintado.tamano * 0.8),
            reason: 'se midió con la letra de prueba, no con Inter',
          );
          final campo = tester.getRect(find.byKey(llaveClave));
          final entrar = tester.getRect(find.byKey(llaveEntrar));
          expect(pintado.derecha, closeTo(campo.right, 1), reason: 'campo ${campo.right}');
          expect(pintado.derecha, closeTo(entrar.right, 1), reason: 'entrar ${entrar.right}');
          expect(pintado.lineas, 1, reason: 'el enlace no debería partirse en dos líneas');
          // Y la zona de toque sigue en 48 de alto, dentro de la columna.
          final zona = tester.getRect(find.byKey(llaveRecuperar));
          expect(zona.height, greaterThanOrEqualTo(48));
          expect(zona.right, lessThanOrEqualTo(campo.right + 0.5));
          expect(zona.left, greaterThanOrEqualTo(campo.left));
        });
      }
    }
  });

  // «¿No tenés cuenta? Registrate» va con `textAlign: center`: a texto grande se parte en renglones y
  // cada uno queda centrado como el resto de la pantalla (QA de #309, destapado en #343). Se mide
  // cada renglón sin el espacio con que termina (`renglonesPintados`): ese espacio entra en la caja
  // aunque no se pinte y corría el centro 3,92 dp.
  group(
    '«Registrate» con la letra real: cada renglón queda centrado como el resto de la pantalla',
    () {
      for (final (tam, escala, partido) in [
        (const Size(412, 915), 2.0, true),
        (const Size(390, 844), 2.0, true),
        (const Size(360, 640), 2.0, true),
        (const Size(320, 568), 2.0, true),
        (const Size(412, 915), 1.0, false),
        (const Size(360, 640), 1.0, false),
      ]) {
        testWidgets('a ${tam.width.toInt()}x${tam.height.toInt()}, texto ×$escala: '
            '${partido ? 'se parte en renglones y cada uno' : 'el renglón único'} queda centrado', (
          tester,
        ) async {
          fijarPantallaLogin(tester, tam, texto: escala);
          await llegarALogin(tester, PantallaLogin.inicial, fuentesReales: true);
          await tester.ensureVisible(find.byKey(llaveRegistro));
          await tester.pumpAndSettle();

          final render = tester.renderObject<RenderParagraph>(
            find.descendant(of: find.byKey(llaveRegistro), matching: find.byType(RichText)).first,
          );
          expect(
            render.text.toPlainText(),
            textoRegistro,
            reason: 'el texto del enlace cambió: revisar la medida',
          );
          final renglones = renglonesPintados(render);
          if (partido) {
            expect(
              renglones.length,
              greaterThanOrEqualTo(2),
              reason: 'se esperaba un texto partido',
            );
          } else {
            expect(renglones.length, 1, reason: 'a este tamaño entra en un renglón');
          }
          for (final r in renglones) {
            final centro = (r.izquierda + r.derecha) / 2;
            expect(
              centro,
              closeTo(tam.width / 2, 1),
              reason: 'renglón de ${r.izquierda} a ${r.derecha}',
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    },
  );
}
