// El aviso del carácter que no va («Revisá el email: no puede llevar tildes, ñ, espacios ni
// comas.», 62 caracteres) a texto grande en un teléfono chico, en las cuatro pantallas (#353): se
// lee entero, sin puntos suspensivos ni desborde (las guías de accesibilidad, a 390×844 y texto
// 1.0, en `email_formato_353_test.dart`). Va en su propio archivo porque carga la letra real (con la
// de prueba, de cuadrados, el corte de renglones no es el real) y eso cambia las medidas de todo el
// archivo.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/casos_email.dart';
import '../helpers/email_formato_353_arnes.dart';

void main() {
  setUpAll(cargarFuentesReales);

  for (final pantalla in pantallasEmail) {
    group('${pantalla.nombre} — el aviso del email a texto grande (#353)', () {
      for (final escala in [1.0, 2.0]) {
        testWidgets('a 360×640 y texto $escala el aviso se lee entero, dentro de la pantalla', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          final armada = await pantalla.armar(tester, tamano: const Size(360, 640), escala: escala);

          await armada.enviar('lucía@correo.com');

          final aviso = find.text(avisoCaracterNoPermitido);
          expect(aviso, findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(aviso);
          await tester.pumpAndSettle();
          final rect = tester.getRect(aviso);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(640));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(
            tester.renderObject<RenderParagraph>(aviso).didExceedMaxLines,
            isFalse,
            reason: 'el aviso quedó cortado con puntos suspensivos',
          );
          semantica.dispose();
        });
      }
    });
  }
}
