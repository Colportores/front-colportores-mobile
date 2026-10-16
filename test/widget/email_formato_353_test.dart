// El formato del email, el mismo en las cuatro pantallas (#353, seguimiento del QA del PR #351):
// login, registro, reenvío de la verificación y recuperación de contraseña.
//
// Un email con un carácter que el servidor no acepta (tilde, ñ, espacio, coma, comillas…) dice lo
// mismo en las cuatro: «Revisá el email: no puede llevar tildes, ñ, espacios ni comas.». Los demás
// casos (falta algo, `..`, punto al final) siguen con el texto de cada pantalla, y los raros pero
// válidos tienen que salir al servidor. Los casos completos están en los tests de dominio
// (`validador_email_test.dart` y los de los cuatro casos de uso): acá, los del QA y la decisión.
// El aviso a texto grande en un teléfono chico, en `email_formato_353_geometria_test.dart`.
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart' show guiasDeAccesibilidad;
import '../helpers/casos_email.dart';
import '../helpers/email_formato_353_arnes.dart';

/// Del QA del PR #351 y de la decisión del 10/10 (los demás casos, en los tests de dominio).
const _conCaracterQueNoVa = [
  'lucia,@correo.com',
  '"lucia",@correo.com',
  'lucía@correo.com',
  'lu cia@correo.com',
];
const _incompletos = ['lucia@correo.com.', 'lucia@correo..com', 'a@b..co'];
const _validosRaros = ["o'neill@correo.com", 'lucia.perez+campania@correo.com.uy'];

void main() {
  for (final pantalla in pantallasEmail) {
    group('${pantalla.nombre} — formato del email (#353)', () {
      for (final email in _conCaracterQueNoVa) {
        testWidgets('«$email» dice que no puede llevar tildes, ñ, espacios ni comas y no sale', (
          tester,
        ) async {
          final armada = await pantalla.armar(tester);

          await armada.enviar(email);

          expect(find.text(avisoCaracterNoPermitido), findsOneWidget);
          expect(find.text(pantalla.textoIncompleto), findsNothing);
          expect(armada.salidas(), 0, reason: 'un email que el servidor rechaza no se manda');
          expect(armada.botonHabilitado(), isTrue);
        });
      }

      for (final email in _incompletos) {
        testWidgets('«$email» sigue con el texto de la pantalla y no sale', (tester) async {
          final armada = await pantalla.armar(tester);

          await armada.enviar(email);

          expect(find.text(pantalla.textoIncompleto), findsOneWidget);
          expect(find.text(avisoCaracterNoPermitido), findsNothing);
          expect(armada.salidas(), 0);
          expect(armada.botonHabilitado(), isTrue);
        });
      }

      for (final email in _validosRaros) {
        testWidgets('«$email» es raro pero válido: pasa y sale al servidor', (tester) async {
          final armada = await pantalla.armar(tester);

          await armada.enviar(email);

          expect(find.text(avisoCaracterNoPermitido), findsNothing);
          expect(find.text(pantalla.textoIncompleto), findsNothing);
          expect(armada.salidas(), 1);
        });
      }

      testWidgets('corregir el email después del aviso lleva a enviarlo', (tester) async {
        final armada = await pantalla.armar(tester);
        await armada.enviar('lucia,@correo.com');
        expect(find.text(avisoCaracterNoPermitido), findsOneWidget);

        await armada.enviar('lucia@correo.com');

        expect(find.text(avisoCaracterNoPermitido), findsNothing);
        expect(armada.salidas(), 1);
      });

      testWidgets('con el aviso a la vista, a 390×844, la pantalla cumple las guías de '
          'accesibilidad', (tester) async {
        final semantica = tester.ensureSemantics();
        final armada = await pantalla.armar(tester, tamano: const Size(390, 844));

        await armada.enviar('lucía@correo.com');

        expect(find.text(avisoCaracterNoPermitido), findsOneWidget);
        await guiasDeAccesibilidad(tester);
        semantica.dispose();
      });
    });
  }
}
