// QA de #309 (PR #341): el enlace de recuperación y «Registrate» se apagan con «Entrar» en vuelo
// (login 1a/1b y vista 17, A01 a A04). Complementa `qa_login_sin_mantener_sesion_306_test.dart` con
// los cruces que ese archivo deja sin probar: «Registrate» con su semántica y con el servidor
// contestando que sí, la señal que vuelve y se va en 17-A02, el teclado del sistema («Listo»), el
// teclado abierto, el recorrido de Tab una vez que el intento terminó y las cuatro guías de
// accesibilidad en las cuatro pantallas con enlace a 360x640 y 412x915, texto ×1 y ×2. Las guías
// van con la letra de prueba de `flutter_test`: `textContrastGuideline` mide píxeles y con la
// tipografía real da falsos negativos en el texto chico (10 y 11 px) que este PR no toca. La
// alineación con la tipografía real está en `qa_login_enlace_309_medidas_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';
import '../helpers/qa_login_enlace_309_arnes.dart';

void main() {
  group('«Registrate» con «Entrar» en vuelo (la extensión del PR)', () {
    testWidgets('en vuelo es un botón apagado con su nombre y su zona de 48 de alto, sin acción de '
        'tocar; al fallar el login vuelve a andar', (tester) async {
      final semantica = tester.ensureSemantics();
      fijarPantallaLogin(tester, const Size(390, 844));
      final e = await llegarALogin(tester, PantallaLogin.inicial);
      await tester.ensureVisible(find.byKey(llaveRegistro));
      await tester.pumpAndSettle();
      final antes = tester.getRect(find.byKey(llaveRegistro));
      expect(
        tester.getSemantics(find.byKey(llaveRegistro)),
        isSemantics(
          label: textoRegistro,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      final demora = await dejarEnVuelo(tester, e, PantallaLogin.inicial);

      expect(tester.getRect(find.byKey(llaveRegistro)), antes, reason: 'conserva su lugar');
      expect(antes.height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(find.byKey(llaveRegistro)),
        isSemantics(
          label: textoRegistro,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      await tester.tap(find.byKey(llaveRegistro), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RegistroPage), findsNothing);

      demora.complete();
      await tester.pumpAndSettle();
      expect(estaApagado(tester, llaveRegistro), isFalse);
      await tester.ensureVisible(find.byKey(llaveRegistro));
      await tester.tap(find.byKey(llaveRegistro));
      await tester.pumpAndSettle();
      expect(find.byType(RegistroPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RegistroPage), findsNothing);
      semantica.dispose();
    });

    testWidgets('si el servidor contesta que sí, ni el registro ni la recuperación quedan apilados '
        'sobre el inicio, aunque se hayan tocado los dos en vuelo', (tester) async {
      final e = await llegarALogin(tester, PantallaLogin.inicial);
      final demora = await dejarEnVuelo(tester, e, PantallaLogin.inicial, clave: claveAna);

      await tester.tap(find.byKey(llaveRegistro), warnIfMissed: false);
      await tester.tap(find.byKey(llaveRecuperar), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RegistroPage), findsNothing);
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      demora.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(llaveInicio), findsOneWidget);
      expect(find.byType(RegistroPage), findsNothing);
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
    });

    testWidgets('17-A02: con la señal que vuelve y se va a mitad del intento, el enlace aparece y '
        'desaparece sin trabar nada, y «Registrate» queda apagado solo mientras dura el intento', (
      tester,
    ) async {
      fijarPantallaLogin(tester, const Size(390, 844));
      final e = await llegarALogin(tester, PantallaLogin.a02, tipo: TipoConexion.sinConexion);
      expect(find.byKey(llaveRecuperar), findsNothing);
      expect(estaApagado(tester, llaveRegistro), isFalse);

      e.conexion.cambiarA(TipoConexion.wifi);
      await tester.pumpAndSettle();
      expect(find.byKey(llaveRecuperar), findsOneWidget);
      final demora = await dejarEnVuelo(tester, e, PantallaLogin.a02);
      expect(estaApagado(tester, llaveRecuperar), isTrue);
      expect(estaApagado(tester, llaveRegistro), isTrue);

      // La señal se cae con el intento a mitad: el enlace sale del árbol (17-A02 no lo dibuja).
      e.conexion.cambiarA(TipoConexion.sinConexion);
      await tester.pump();
      expect(find.byKey(llaveRecuperar), findsNothing);
      expect(estaApagado(tester, llaveRegistro), isTrue);
      expect(tester.takeException(), isNull);

      demora.complete();
      await tester.pumpAndSettle();
      expect(
        estaApagado(tester, llaveRegistro),
        isFalse,
        reason: 'no queda trabado tras el intento',
      );
      expect(find.byKey(llaveRecuperar), findsNothing);

      // Vuelve la señal: el enlace reaparece habilitado, no apagado por un intento que ya terminó.
      e.conexion.cambiarA(TipoConexion.wifi);
      await tester.pumpAndSettle();
      expect(find.byKey(llaveRecuperar), findsOneWidget);
      expect(estaApagado(tester, llaveRecuperar), isFalse);
      await tester.ensureVisible(find.byKey(llaveRecuperar));
      await tester.tap(find.byKey(llaveRecuperar));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
    });
  });

  group('El intento sale por el teclado del sistema («Listo») y con el teclado abierto', () {
    testWidgets('«Listo» en la contraseña deja el intento en vuelo con el enlace y «Registrate» '
        'apagados; un segundo «Listo» no manda otro intento; al fallar, todo vuelve', (
      tester,
    ) async {
      fijarPantallaLogin(tester, const Size(360, 640), teclado: 280);
      final e = await llegarALogin(tester, PantallaLogin.inicial);
      final demora = Completer<void>();
      e.remoto.demoraIniciarSesion = demora;
      await tester.enterText(find.byKey(llaveCorreo), correoAna);
      await tester.enterText(find.byKey(llaveClave), 'incorrecta1');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(e.remoto.llamadasIniciarSesion, 1);
      expect(estaApagado(tester, llaveRecuperar), isTrue);
      expect(estaApagado(tester, llaveRegistro), isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(e.remoto.llamadasIniciarSesion, 1, reason: 'el segundo «Listo» no manda otro intento');

      demora.complete();
      await tester.pumpAndSettle();
      expect(estaApagado(tester, llaveRecuperar), isFalse);
      expect(estaApagado(tester, llaveRegistro), isFalse);
      // Lo tipeado no se pierde tras el error.
      expect(tester.widget<TextField>(find.byKey(llaveCorreo)).controller!.text, correoAna);
      expect(tester.widget<TextField>(find.byKey(llaveClave)).controller!.text, 'incorrecta1');
    });

    for (final escala in const [1.0, 2.0]) {
      testWidgets('con el teclado abierto (280) a 360x640, texto ×$escala: en vuelo el enlace '
          'apagado se alcanza desplazando, sin overflow y con las guías; al terminar abre la '
          'recuperación', (tester) async {
        fijarPantallaLogin(tester, const Size(360, 640), texto: escala, teclado: 280);
        final e = await llegarALogin(tester, PantallaLogin.inicial);
        final demora = await dejarEnVuelo(tester, e, PantallaLogin.inicial);

        await tester.ensureVisible(find.byKey(llaveRecuperar));
        await tester.pump();
        expect(estaApagado(tester, llaveRecuperar), isTrue);
        final zona = tester.getRect(find.byKey(llaveRecuperar));
        expect(zona.height, greaterThanOrEqualTo(48));
        await tester.tap(find.byKey(llaveRecuperar), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(RecuperacionPasswordPage), findsNothing);
        await guiasLogin(tester);

        demora.complete();
        await tester.pumpAndSettle();
        expect(estaApagado(tester, llaveRecuperar), isFalse);
        await tester.ensureVisible(find.byKey(llaveRecuperar));
        await tester.tap(find.byKey(llaveRecuperar));
        await tester.pumpAndSettle();
        expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      });
    }
  });

  group('Recorrido de Tab: apagados en vuelo, de vuelta cuando el intento termina', () {
    for (final pantalla in [PantallaLogin.inicial, PantallaLogin.a01]) {
      testWidgets('${pantalla.nombre}: tras un intento fallido, Tab vuelve a pasar por el enlace y '
          'por «Registrate»', (tester) async {
        fijarPantallaLogin(tester, const Size(412, 915));
        final e = await llegarALogin(tester, pantalla);
        final demora = await dejarEnVuelo(tester, e, pantalla);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        final enVuelo = await tabularLogin(tester, 3);
        expect(enVuelo, isNot(contains('recuperar')));
        expect(enVuelo, isNot(contains('registro')));

        demora.complete();
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        final despues = await tabularLogin(tester, 8);

        expect(despues, containsAll(['recuperar', 'entrar', 'registro']));
        expect(despues, isNot(contains('otro')));
      });
    }
  });

  group('Guías de accesibilidad con el intento en vuelo y la tipografía real', () {
    for (final pantalla in pantallasConEnlace) {
      for (final tam in const [Size(360, 640), Size(412, 915)]) {
        for (final escala in const [1.0, 2.0]) {
          testWidgets('${pantalla.nombre} en vuelo a ${tam.width.toInt()}x${tam.height.toInt()}, '
              'texto ×$escala: enlace y «Registrate» apagados, de 48 de alto, sin overflow y con '
              'las cuatro guías', (tester) async {
            fijarPantallaLogin(tester, tam, texto: escala);
            final e = await llegarALogin(tester, pantalla);
            final demora = await dejarEnVuelo(tester, e, pantalla);

            expect(estaApagado(tester, llaveRecuperar), isTrue);
            expect(estaApagado(tester, llaveRegistro), isTrue);
            for (final llave in [llaveRecuperar, llaveRegistro]) {
              await tester.ensureVisible(find.byKey(llave));
              await tester.pump();
              final r = tester.getRect(find.byKey(llave));
              expect(r.height, greaterThanOrEqualTo(48), reason: '$llave mide $r');
              expect(r.width, greaterThanOrEqualTo(48), reason: '$llave mide $r');
            }
            await guiasLogin(tester);

            demora.complete();
            await tester.pumpAndSettle();
            expect(estaApagado(tester, llaveRecuperar), isFalse);
            expect(estaApagado(tester, llaveRegistro), isFalse);
            await guiasLogin(tester);
          });
        }
      }
    }
  });
}
