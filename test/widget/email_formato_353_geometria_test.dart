// El aviso del carácter que no va («Revisá el email: no puede llevar tildes, ñ, espacios ni
// comas.», 62 caracteres) y el de la dirección que el servidor rechaza («Revisá el email: no
// podemos mandar correos a esa dirección.», 59) a texto grande en un teléfono chico, en las cuatro
// pantallas (#353): se leen enteros, sin puntos suspensivos ni desborde (las guías de accesibilidad,
// a 390×844 y texto 1.0, en `email_formato_353_test.dart`). La recuperación de contraseña no
// muestra el segundo: lo enmascara (HU-AUTH-004, #363). Va en su propio archivo porque carga la
// letra real (con la de prueba, de cuadrados, el corte de renglones no es el real) y eso cambia las
// medidas de todo el archivo.
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/domain/services/validador_email.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show Scrollable;
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
        // La recuperación no muestra el rechazo del servidor (#363): lo trata como un envío.
        if (!pantalla.rechazoDelServidorSeVe && texto == avisoDireccionRechazada) continue;
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
  // «Verificá tu cuenta» con el correo del alta conocido: sin campo, el rechazo del servidor va al
  // aviso general y dice qué hacer (#363). Es más largo que el del campo (87 caracteres).
  group('Verificá tu cuenta con el correo conocido — el aviso de la dirección rechazada a texto '
      'grande (#363)', () {
    for (final (tam, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(320, 568), 1.0),
      (const Size(320, 568), 2.0),
      (const Size(320, 568), 3.0),
    ]) {
      testWidgets('a ${tam.width.toInt()}×${tam.height.toInt()} y texto $escala el aviso se lee '
          'entero, dentro de la pantalla', (tester) async {
        final semantica = tester.ensureSemantics();
        await montarVerificacionConCorreoConocido(tester, tamano: tam, escala: escala);

        const reenviar = Key('verificacion_email_reenviar');
        await tester.ensureVisible(find.byKey(reenviar));
        await tester.tap(find.byKey(reenviar));
        await tester.pumpAndSettle();

        final aviso = find.text(ValidadorEmail.avisoDireccionRechazadaSinCampo);
        expect(aviso, findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          tester.renderObject<RenderParagraph>(aviso).didExceedMaxLines,
          isFalse,
          reason: 'el aviso quedó cortado con puntos suspensivos',
        );
        // A 320×568 y texto al 300 % el aviso es más alto que la pantalla: se lee desplazando. Los
        // dos extremos tienen que poder verse (ninguna parte queda fuera de alcance).
        await tester.ensureVisible(aviso);
        await tester.pumpAndSettle();
        expect(tester.getRect(aviso).top, greaterThanOrEqualTo(0), reason: 'el principio se ve');
        await Scrollable.ensureVisible(tester.element(aviso), alignment: 1);
        await tester.pumpAndSettle();
        final rect = tester.getRect(aviso);
        expect(rect.bottom, lessThanOrEqualTo(tam.height), reason: 'el final se ve');
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(tam.width));
        semantica.dispose();
      });
    }
  });
}
