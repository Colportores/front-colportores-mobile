// «Olvidé mi contraseña» cuando el servidor rechaza la dirección (400 `email_address_invalid`,
// #363, seguimiento de #354). HU-AUTH-004: «la respuesta a la solicitud nunca debe revelar si el
// email existe o no». El servidor solo rechaza una dirección al armar el correo, o sea solo para una
// cuenta que existe: mostrarlo la distinguiría de una que no existe. Por eso la pantalla hace
// exactamente lo mismo que con un email sin cuenta: el mensaje genérico, la hora del envío guardada
// y «Reenviar en Ns». El caso base de las cuatro pantallas está en `email_formato_353_test.dart`;
// acá, que sea la misma pantalla y lo que le pasa al volver, reintentar y tocar dos veces.
import 'dart:async';

import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/casos_email.dart';
import '../helpers/qa_vista14_351_arnes.dart';

/// Lo que dice la pantalla, renglón por renglón (con el reloj quieto, la espera es siempre la misma).
List<String> _textosDeLaPantalla(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(find.byType(Text)))
    texto.data ?? texto.textSpan?.toPlainText() ?? '',
];

AuthRemoteDataSourceEnMemoria _remotoQueRechaza() =>
    remotoQa()..fallaAlSolicitarRecuperacion = const EmailInvalidoException();

/// Pide el enlace con [email] (el botón de A01) y espera a que la pantalla se asiente.
Future<void> _pedir(WidgetTester tester, String email) async {
  await escribirQa(tester, email);
  await tocarQa(tester, enviarQa);
  await tester.pumpAndSettle();
}

void main() {
  late RelojQa reloj;

  setUp(() => reloj = RelojQa(DateTime.utc(2026, 10, 16, 10)));

  group('Recuperación de contraseña — el servidor rechaza la dirección (HU-AUTH-004, #363)', () {
    testWidgets(
      'dado un email cuya cuenta existe y que el servidor rechaza, cuando pide el enlace, '
      'la pantalla es la misma que con un email sin cuenta',
      (tester) async {
        await montarQa(tester, remote: _remotoQueRechaza(), ahora: reloj.call);
        await _pedir(tester, correoQa);
        final conRechazo = _textosDeLaPantalla(tester);
        final reenviarHabilitadoConRechazo = habilitadoQa(tester, reenviarQa);
        await tester.pumpWidget(const SizedBox());

        await montarQa(tester, remote: remotoQa(), ahora: reloj.call);
        await _pedir(tester, 'otra.persona@correo.com');
        final sinCuenta = _textosDeLaPantalla(tester);

        expect(conRechazo, sinCuenta);
        expect(conRechazo, contains(mensajeNeutroQa));
        expect(conRechazo, contains('Reenviar en 60s'));
        expect(conRechazo, isNot(contains(avisoDireccionRechazada)));
        expect(reenviarHabilitadoConRechazo, habilitadoQa(tester, reenviarQa));
        expect(reenviarHabilitadoConRechazo, isFalse, reason: 'la espera de 60 s corre');
      },
    );

    testWidgets('cuando pide el enlace, guarda la hora del envío como un envío que salió', (
      tester,
    ) async {
      final envios = EnviosQa();
      await montarQa(tester, remote: _remotoQueRechaza(), ultimoEnvio: envios, ahora: reloj.call);

      await _pedir(tester, correoQa);

      expect(envios.guardados, [reloj.ahora]);
    });

    testWidgets('cuando vuelve al login y entra de nuevo, la espera sigue y no hay aviso de la '
        'dirección', (tester) async {
      final envios = EnviosQa();
      await montarQa(tester, remote: _remotoQueRechaza(), ultimoEnvio: envios, ahora: reloj.call);
      await _pedir(tester, correoQa);
      await tocarQa(tester, volverQa);
      await tester.pumpAndSettle();
      await pasarQa(tester, reloj, const Duration(seconds: 20));

      await tester.tap(llaveQa('abrir_recuperacion'));
      await tester.pumpAndSettle();

      expect(find.text('Podés pedir otro enlace en 40s.'), findsOneWidget);
      expect(habilitadoQa(tester, enviarQa), isFalse);
      expect(find.text(avisoDireccionRechazada), findsNothing);
      expect(avisoGeneralQa, findsNothing);
    });

    testWidgets('cuando termina la espera y pide otro enlace, vuelve a ser el mismo mensaje y la '
        'espera arranca de nuevo', (tester) async {
      final envios = EnviosQa();
      await montarQa(tester, remote: _remotoQueRechaza(), ultimoEnvio: envios, ahora: reloj.call);
      await _pedir(tester, correoQa);
      final primerEnvio = reloj.ahora;
      await pasarQa(tester, reloj, const Duration(seconds: 60));
      expect(find.text('Reenviar enlace'), findsOneWidget);
      expect(habilitadoQa(tester, reenviarQa), isTrue);

      await tocarQa(tester, reenviarQa);
      await tester.pumpAndSettle();

      expect(find.text(mensajeNeutroQa), findsOneWidget);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(habilitadoQa(tester, reenviarQa), isFalse);
      expect(find.text(avisoDireccionRechazada), findsNothing);
      expect(envios.guardados, [primerEnvio, reloj.ahora]);
    });

    testWidgets('con la solicitud en vuelo, un segundo toque no pide otra vez y al contestar queda '
        'una sola hora guardada', (tester) async {
      final remoto = _remotoQueRechaza()..demoraRecuperacion = Completer<void>();
      final envios = EnviosQa();
      await montarQa(tester, remote: remoto, ultimoEnvio: envios, ahora: reloj.call);
      await escribirQa(tester, correoQa);

      await tocarQa(tester, enviarQa);
      await tester.pump();
      expect(habilitadoQa(tester, enviarQa), isFalse, reason: 'mientras envía el botón se apaga');
      await tocarQa(tester, enviarQa);
      await tester.pump();
      remoto.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();

      expect(find.text(mensajeNeutroQa), findsOneWidget);
      expect(envios.guardados, hasLength(1));
    });

    testWidgets('a 360×640 y con el texto al 200 % se lee el mensaje y la espera, sin desborde', (
      tester,
    ) async {
      await montarQa(
        tester,
        remote: _remotoQueRechaza(),
        ahora: reloj.call,
        tamano: const Size(360, 640),
        texto: 2,
      );

      await _pedir(tester, correoQa);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(exitoQa);
      expect(find.text(mensajeNeutroQa), findsOneWidget);
      await tester.ensureVisible(reenviarQa);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
    });

    testWidgets('el mensaje se anuncia al lector de pantalla, igual que con un email sin cuenta', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarQa(tester, remote: _remotoQueRechaza(), ahora: reloj.call);

      await _pedir(tester, correoQa);

      expect(tester.getSemantics(exitoQa), isSemantics(isLiveRegion: true));
      semantica.dispose();
    });
  });
}
