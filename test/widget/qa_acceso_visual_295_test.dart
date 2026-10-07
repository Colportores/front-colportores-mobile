// QA visual del acceso (#265, PR #295), ronda 1: lo que solo se ve con las fuentes reales de la app
// (Inter, Source Serif 4, JetBrains Mono) y por eso va en un archivo aparte: cargarlas cambia el
// ancho de todo el texto del archivo.
//
// Los hallazgos de la ronda 1 que esta suite dejaba con `skip:` quedaron arreglados (ronda 1 de la
// revisión del PR #295): ningún test de acá está salteado.
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';
import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;

/// `true` si el texto se pinta entero: en una sola línea y sin recortarse con «…».
bool _seVeEntero(WidgetTester tester, Finder texto) {
  final parrafo = tester.renderObject<RenderParagraph>(texto);
  final natural = parrafo.getMaxIntrinsicWidth(double.infinity);
  return parrafo.size.width + 0.5 >= natural;
}

void main() {
  setUpAll(cargarFuentesReales);

  group('Acceso — revisión visual con las fuentes reales', () {
    for (final ancho in [360.0, 390.0]) {
      testWidgets('el enlace «¿Olvidaste tu clave?» se lee entero a ${ancho.toInt()} de ancho', (
        tester,
      ) async {
        fijarPantalla(tester, Size(ancho, 800));
        await montarAcceso(tester, home: const LoginPage());
        await tester.pumpAndSettle();

        expect(_seVeEntero(tester, find.text('¿Olvidaste tu clave?')), isTrue);
      });
    }

    testWidgets('el enlace «¿Olvidaste tu clave?» se lee entero a 412 de ancho', (tester) async {
      fijarPantalla(tester, const Size(412, 915));
      await montarAcceso(tester, home: const LoginPage());
      await tester.pumpAndSettle();

      expect(_seVeEntero(tester, find.text('¿Olvidaste tu clave?')), isTrue);
    });

    testWidgets('con el texto al 200 % el enlace de recuperación se lee entero (360x640)', (
      tester,
    ) async {
      fijarPantalla(tester, const Size(360, 640));
      await montarAcceso(tester, home: const LoginPage(), escala: 2);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('¿Olvidaste tu clave?'));

      expect(_seVeEntero(tester, find.text('¿Olvidaste tu clave?')), isTrue);
    });

    testWidgets(
      'una casilla sin marcar no se pinta igual que una marcada (términos del registro)',
      (tester) async {
        fijarPantalla(tester, const Size(390, 844));
        await montarAcceso(tester, home: const RegistroPage());
        await tester.pumpAndSettle();

        final casilla = find.byKey(const Key('registro_terminos'));
        await tester.ensureVisible(casilla);
        final tema = Theme.of(tester.element(casilla)).checkboxTheme;
        final sinMarcar = tema.fillColor!.resolve(<WidgetState>{});
        final marcada = tema.fillColor!.resolve(<WidgetState>{WidgetState.selected});

        expect(sinMarcar, isNot(marcada));
      },
    );
  });
}
