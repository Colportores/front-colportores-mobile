// El aviso del carácter que no va («Revisá el email: no puede llevar tildes, ñ, espacios ni
// comas.», 62 caracteres) y el de la dirección que el servidor rechaza («Revisá el email: no
// podemos mandar correos a esa dirección.», 59) a texto grande en un teléfono chico, en las cuatro
// pantallas (#353): se leen enteros, sin puntos suspensivos ni desborde (las guías de accesibilidad,
// a 390×844 y texto 1.0, en `email_formato_353_test.dart`). Va en su propio archivo porque carga la
// letra real (con la de prueba, de cuadrados, el corte de renglones no es el real) y eso cambia las
// medidas de todo el archivo.
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/casos_email.dart';
import '../helpers/email_formato_353_arnes.dart';

void main() {
  setUpAll(cargarFuentesReales);

  // Cada aviso, con lo que hay que hacer para que la pantalla lo muestre.
  final avisos = <(String, String, String, void Function(ArmadaEmail))>[
    ('del carácter que no va', avisoCaracterNoPermitido, 'lucía@correo.com', (_) {}),
    (
      'de la dirección que el servidor rechaza',
      avisoDireccionRechazada,
      'lucia@gmial.com',
      (armada) => armada.fallarCon(const EmailInvalidoException()),
    ),
  ];

  for (final pantalla in pantallasEmail) {
    group('${pantalla.nombre} — el aviso del email a texto grande (#353)', () {
      for (final (cual, texto, email, preparar) in avisos) {
        for (final (tam, escala) in [
          (const Size(360, 640), 1.0),
          (const Size(360, 640), 2.0),
          (const Size(320, 568), 1.0),
          (const Size(320, 568), 2.0),
          (const Size(320, 568), 3.0),
        ]) {
          testWidgets('a ${tam.width.toInt()}×${tam.height.toInt()} y texto $escala el aviso $cual '
              'se lee entero, dentro de la pantalla', (tester) async {
            final semantica = tester.ensureSemantics();
            final armada = await pantalla.armar(tester, tamano: tam, escala: escala);
            preparar(armada);

            await armada.enviar(email);

            final aviso = find.text(texto);
            expect(aviso, findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(aviso);
            await tester.pumpAndSettle();
            final rect = tester.getRect(aviso);
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(tam.height));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(tam.width));
            expect(
              tester.renderObject<RenderParagraph>(aviso).didExceedMaxLines,
              isFalse,
              reason: 'el aviso quedó cortado con puntos suspensivos',
            );
            semantica.dispose();
          });
        }
      }
    });
  }
}
