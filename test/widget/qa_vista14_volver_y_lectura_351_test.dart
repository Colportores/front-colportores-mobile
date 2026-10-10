// QA del PR #351 (#313 y #318, vista 14 «Olvidé mi contraseña», HU-AUTH-004/005): lo que
// `recuperacion_password_page_test.dart` no recorre. Cada estado del diseño (A01 a A06) y cada
// estado nuevo de este PR (A05 con sesión abierta, «Volver al login» apagado con el reenvío en
// vuelo, el aviso de lectura lenta y la hora guardada en el futuro) en los dos teléfonos del
// checklist (360×640 y 412×915) con el texto al 100 %, 200 % y 300 %; el atrás del sistema en cada
// estado; los límites del tope de 3 s; y los casos en que el almacén no contesta o falla.
//
// Los dos tests con `skip` (comentario `// skip: QA #351 — …`) documentan un hallazgo de la QA del
// PR #351 (el comentario «QA ronda 1»): el implementador les saca el `skip` cuando lo arregla.
import 'dart:async';

import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_envio_recuperacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/solicitar_recuperacion_password_use_case.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/logger_mudo.dart';
import '../helpers/qa_vista14_351_arnes.dart';

void main() {
  group('QA #351 · A05 «Volver» / «Volver al login» y el atrás del sistema (#313, #318)', () {
    for (final (nombre, conSesion, rotulo) in [
      ('sin sesión', false, 'Volver al login'),
      ('con la sesión abierta', true, 'Volver'),
    ]) {
      group(nombre, () {
        late AuthRemoteDataSourceEnMemoria remote;
        late RelojQa reloj;

        setUp(() {
          remote = remotoQa();
          reloj = RelojQa(DateTime(2026, 10, 10, 10));
        });

        testWidgets('A05 quieta: el atrás del sistema sale a la pantalla de abajo y no toca la '
            'sesión', (tester) async {
          final container = await montarQa(
            tester,
            remote: remote,
            conSesion: conSesion,
            ahora: reloj.call,
          );
          final antes = container.read(sesionProvider).value;
          await aA05Qa(tester);
          expect(find.descendant(of: volverQa, matching: find.text(rotulo)), findsOneWidget);

          expect(await atrasDelSistemaQa(tester), isFalse, reason: 'el atrás sale de A05');
          expect(find.text('pantalla de abajo'), findsOneWidget);
          expect(container.read(sesionProvider).value, antes, reason: 'la sesión sigue igual');
        });

        testWidgets('A05 con el reenvío en vuelo: el atrás del sistema no saca; al terminar, sí', (
          tester,
        ) async {
          final container = await montarQa(
            tester,
            remote: remote,
            conSesion: conSesion,
            ahora: reloj.call,
          );
          final antes = container.read(sesionProvider).value;
          await aA05Qa(tester);
          await pasarQa(tester, reloj, const Duration(seconds: 60));
          remote.demoraRecuperacion = Completer<void>();
          await tester.tap(reenviarQa);
          await tester.pump();
          expect(find.text('Enviando…'), findsOneWidget);

          expect(
            await atrasDelSistemaQa(tester),
            isTrue,
            reason: 'con el reenvío en vuelo no sale',
          );
          expect(habilitadoQa(tester, volverQa), isFalse);

          remote.demoraRecuperacion!.complete();
          await tester.pumpAndSettle();
          expect(pedidosQa(remote), 2);
          expect(habilitadoQa(tester, volverQa), isTrue);
          expect(await atrasDelSistemaQa(tester), isFalse, reason: 'terminó: el atrás sale');
          expect(find.text('pantalla de abajo'), findsOneWidget);
          expect(container.read(sesionProvider).value, antes);
        });

        testWidgets('reenvío que falla por falta de red: aviso con la acción a mano, «$rotulo» '
            'y «Reenviar» vivos; al volver la red, el reintento llega a A05', (tester) async {
          await montarQa(tester, remote: remote, conSesion: conSesion, ahora: reloj.call);
          await aA05Qa(tester);
          await pasarQa(tester, reloj, const Duration(seconds: 60));
          remote.simularSinConexion = true;
          await tester.tap(reenviarQa);
          await tester.pumpAndSettle();

          expect(find.text(sinConexionQa), findsOneWidget);
          expect(habilitadoQa(tester, volverQa), isTrue);
          expect(habilitadoQa(tester, reenviarQa), isTrue);
          expect(find.text('Enviando…'), findsNothing);

          remote.simularSinConexion = false;
          await tester.tap(reenviarQa);
          await tester.pumpAndSettle();
          expect(find.text(sinConexionQa), findsNothing, reason: 'el aviso viejo se va');
          expect(find.text('Reenviar en 60s'), findsOneWidget);
          expect(pedidosQa(remote), 2);
        });

        testWidgets('doble toque en «Reenviar»: un solo pedido y «$rotulo» apagado hasta que '
            'termina', (tester) async {
          await montarQa(tester, remote: remote, conSesion: conSesion, ahora: reloj.call);
          await aA05Qa(tester);
          await pasarQa(tester, reloj, const Duration(seconds: 60));
          remote.demoraRecuperacion = Completer<void>();

          await tester.tap(reenviarQa);
          await tester.tap(reenviarQa, warnIfMissed: false);
          await tester.pump();
          remote.demoraRecuperacion!.complete();
          await tester.pumpAndSettle();

          expect(pedidosQa(remote), 2, reason: 'el primer envío y un solo reenvío');
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('A06 de la vista 15 → «Solicitar un enlace nuevo» → A05 → «Volver al login» '
        'vuelve a la pantalla de abajo (sin sesión)', (tester) async {
      final remote = remotoQa();
      await montarQa(tester, remote: remote, viaVencido: true);
      expect(llaveQa('confirmar_recuperacion_vencido'), findsOneWidget);
      await tester.tap(llaveQa('confirmar_recuperacion_pedir_otro'));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);

      await aA05Qa(tester);
      expect(find.text(mensajeNeutroQa), findsOneWidget);
      await tester.tap(volverQa);
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsNothing);
      expect(find.text('pantalla de abajo'), findsOneWidget);
    });

    testWidgets('A06 de la vista 15 con la sesión abierta → A05 dice «Volver» y la sesión '
        'sigue viva al salir', (tester) async {
      final remote = remotoQa();
      final container = await montarQa(tester, remote: remote, conSesion: true, viaVencido: true);
      final antes = container.read(sesionProvider).value;
      expect(antes, isNotNull);
      await tester.tap(llaveQa('confirmar_recuperacion_pedir_otro'));
      await tester.pumpAndSettle();

      await aA05Qa(tester);
      expect(find.descendant(of: volverQa, matching: find.text('Volver')), findsOneWidget);
      await tester.tap(volverQa);
      await tester.pumpAndSettle();
      expect(find.text('pantalla de abajo'), findsOneWidget);
      expect(container.read(sesionProvider).value, antes);
    });
  });

  group('QA #351 · el tope de 3 s a la lectura de la hora guardada (#318)', () {
    late AuthRemoteDataSourceEnMemoria remote;
    late RelojQa reloj;
    late Completer<DateTime?> lectura;
    late EnviosQa envios;

    setUp(() {
      remote = remotoQa();
      reloj = RelojQa(DateTime(2026, 10, 10, 10));
    });

    /// El `Completer` se crea dentro del test: en `setUp` queda fuera de la zona del reloj falso y
    /// sus continuaciones no avanzan con `pump`.
    void armar() {
      lectura = Completer<DateTime?>();
      envios = EnviosQa(lectura: lectura);
    }

    Future<void> montarYPedir(WidgetTester tester, {bool conSesion = false}) async {
      armar();
      await montarQa(
        tester,
        remote: remote,
        conSesion: conSesion,
        ultimoEnvio: envios,
        ahora: reloj.call,
      );
      await escribirQa(tester, correoQa);
      await tocarQa(tester, enviarQa);
      await tester.pump();
    }

    testWidgets('a los 2,9 s sigue «Enviando…»; a los 3 s aparece el aviso, el botón vuelve y '
        'nada se envió', (tester) async {
      await montarYPedir(tester);
      expect(find.text('Enviando…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.text('Enviando…'), findsOneWidget);
      expect(find.text(avisoLentaQa), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(avisoLentaQa), findsOneWidget);
      expect(find.text('Enviando…'), findsNothing);
      expect(find.text('Enviar enlace de recuperación'), findsOneWidget);
      expect(habilitadoQa(tester, enviarQa), isTrue);
      expect(habilitadoQa(tester, atrasQa), isTrue);
      expect(pedidosQa(remote), 0, reason: 'no se manda a ciegas');
      expect(textoDelCampoQa(tester), correoQa, reason: 'lo tipeado no se pierde');
    });

    testWidgets('el aviso es una región viva (lo anuncia TalkBack) y la acción está a mano', (
      tester,
    ) async {
      await montarYPedir(tester);
      await tester.pump(topeQa + const Duration(milliseconds: 100));

      expect(
        find.ancestor(
          of: find.text(avisoLentaQa),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('reintentar tres veces seguidas con el almacén mudo: cada vez 3 s y el aviso; '
        'nunca queda «Enviando…» ni se manda', (tester) async {
      await montarYPedir(tester);
      for (var i = 0; i < 3; i++) {
        await tester.pump(topeQa + const Duration(milliseconds: 100));
        expect(find.text(avisoLentaQa), findsOneWidget, reason: 'vuelta ${i + 1}');
        expect(habilitadoQa(tester, enviarQa), isTrue);
        await tester.tap(enviarQa);
        await tester.pump();
        expect(find.text(avisoLentaQa), findsNothing, reason: 'el aviso viejo se va al reintentar');
        expect(find.text('Enviando…'), findsOneWidget);
      }
      await tester.pump(topeQa + const Duration(milliseconds: 100));
      expect(find.text(avisoLentaQa), findsOneWidget);
      expect(pedidosQa(remote), 0);
    });

    testWidgets('doble toque y «Listo» del teclado durante la espera: una sola espera, un solo '
        'aviso, ningún envío', (tester) async {
      await montarYPedir(tester);
      await tester.tap(enviarQa, warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(topeQa + const Duration(milliseconds: 100));

      expect(find.text(avisoLentaQa), findsOneWidget);
      expect(find.text('Enviando…'), findsNothing);
      expect(pedidosQa(remote), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('durante los 3 s el atrás del sistema y la flecha no sacan; pasado el tope, sí', (
      tester,
    ) async {
      await montarYPedir(tester);
      expect(habilitadoQa(tester, atrasQa), isFalse);
      expect(await atrasDelSistemaQa(tester), isTrue);

      await tester.pump(topeQa);
      await tester.pump(const Duration(milliseconds: 100));
      expect(habilitadoQa(tester, atrasQa), isTrue);
      expect(await atrasDelSistemaQa(tester), isFalse);
      expect(find.text('pantalla de abajo'), findsOneWidget);
    });

    testWidgets('la lectura llega a los 2 s sin espera: el envío sigue solo, sin aviso, y llega a '
        'A05', (tester) async {
      await montarYPedir(tester);
      await tester.pump(const Duration(seconds: 2));
      lectura.complete(null);
      await tester.pumpAndSettle();

      expect(find.text(avisoLentaQa), findsNothing);
      expect(exitoQa, findsOneWidget);
      expect(pedidosQa(remote), 1);
      expect(envios.guardados, hasLength(1));
    });

    testWidgets('la lectura llega a los 2 s con la espera vigente: no se envía, aparece «Podés '
        'pedir otro enlace en Ns.» y el botón no queda en «Enviando…»', (tester) async {
      await montarYPedir(tester);
      await tester.pump(const Duration(seconds: 2));
      lectura.complete(reloj.ahora.subtract(const Duration(seconds: 20)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(avisoLentaQa), findsNothing);
      expect(find.text('Enviando…'), findsNothing);
      expect(pedidosQa(remote), 0);
      expect(find.text('Podés pedir otro enlace en 40s.'), findsOneWidget);
      expect(habilitadoQa(tester, enviarQa), isFalse);
    });

    testWidgets('tras el aviso, la lectura termina tarde con la espera vigente: el aviso se va y '
        'la espera aparece sola', (tester) async {
      await montarYPedir(tester);
      await tester.pump(topeQa + const Duration(milliseconds: 100));
      expect(find.text(avisoLentaQa), findsOneWidget);

      lectura.complete(reloj.ahora.subtract(const Duration(seconds: 3)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(avisoLentaQa), findsNothing);
      expect(esperaQa, findsOneWidget);
      expect(habilitadoQa(tester, enviarQa), isFalse);
    });

    testWidgets('el aviso cabe en 360×640 al 300 % sin desborde y se alcanza el botón', (
      tester,
    ) async {
      armar();
      await montarQa(
        tester,
        remote: remote,
        ultimoEnvio: envios,
        ahora: reloj.call,
        tamano: const Size(360, 640),
        texto: 3,
      );
      await escribirQa(tester, correoQa);
      await tocarQa(tester, enviarQa);
      await tester.pump(topeQa + const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text(avisoLentaQa), findsOneWidget);
      await tester.ensureVisible(enviarQa);
      expect(tester.getRect(enviarQa).bottom, lessThanOrEqualTo(640));
    });

    // skip: QA #351 — F2 (#318): la lectura que llega tarde cuenta la espera desde la hora en que
    // EMPEZÓ a leer (`ahora` se captura antes del `await`), no desde la hora en que terminó. Con un
    // envío hace 20 s y la lectura terminando 10 s después, quedan 30 s; la pantalla dice 40 s.
    testWidgets('la lectura tarda 10 s: la espera que se muestra es la que falta de verdad (30 s '
        'de 60 con el envío hace 30 s), no la que había al empezar a leer', (tester) async {
      armar();
      await montarQa(tester, remote: remote, ultimoEnvio: envios, ahora: reloj.call);
      final envioHace20sAlAbrir = reloj.ahora.subtract(const Duration(seconds: 20));
      await pasarQa(tester, reloj, const Duration(seconds: 10));
      lectura.complete(envioHace20sAlAbrir);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Podés pedir otro enlace en 30s.'), findsOneWidget);
    }, skip: true);
  });

  group('QA #351 · el almacén colgado después de enviar (#318)', () {
    // skip: QA #351 — F1 (#318): el tope de 3 s cubre la LECTURA, pero la escritura de la hora
    // (`await registrar(...)`) no tiene tope. Si el almacén no contesta, el correo ya salió y la
    // pantalla queda en «Enviando…» para siempre: ni A05, ni la flecha, ni el atrás del sistema.
    testWidgets('el correo salió y el almacén no contesta la escritura: pasados 3 s se llega a A05 '
        'y se puede salir', (tester) async {
      final remote = remotoQa();
      final reloj = RelojQa(DateTime(2026, 10, 10, 10));
      final repo = UltimoEnvioRecuperacionRepositoryImpl(AlmacenColgadoQa(), logger: loggerMudo());
      await montarQa(tester, remote: remote, conSesion: true, ultimoEnvio: repo, ahora: reloj.call);
      await escribirQa(tester, correoQa);
      await tocarQa(tester, enviarQa);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(pedidosQa(remote), 1, reason: 'el correo ya salió');
      expect(
        find.text('Enviando…'),
        findsNothing,
        reason: 'nada puede quedar ocupado para siempre',
      );
      expect(exitoQa, findsOneWidget, reason: 'la persona tiene que saber que el enlace salió');
      expect(await atrasDelSistemaQa(tester), isFalse);
    }, skip: true);
  });

  group('QA #351 · la hora guardada en el futuro se corrige sola (#318)', () {
    for (final (nombre, futuro) in [
      ('1 segundo', const Duration(seconds: 1)),
      ('1 hora', const Duration(hours: 1)),
      ('400 días', const Duration(days: 400)),
    ]) {
      testWidgets('guardada $nombre adelante: la espera es de 60 s, nunca más, y se reescribe con '
          'la hora de ahora', (tester) async {
        final reloj = RelojQa(DateTime(2026, 10, 10, 10));
        final envios = EnviosQa(hora: reloj.ahora.add(futuro));
        await montarQa(tester, remote: remotoQa(), ultimoEnvio: envios, ahora: reloj.call);

        expect(find.text('Podés pedir otro enlace en 60s.'), findsOneWidget);
        expect(habilitadoQa(tester, enviarQa), isFalse);
        expect(
          envios.guardados.single.difference(reloj.ahora).abs(),
          lessThan(const Duration(seconds: 1)),
        );
        await pasarQa(tester, reloj, const Duration(seconds: 61));
        expect(esperaQa, findsNothing);
        expect(habilitadoQa(tester, enviarQa), isTrue);
      });
    }

    testWidgets('si la corrección no se puede guardar (el almacén falla), la pantalla sigue en '
        '60 s y no revienta', (tester) async {
      final reloj = RelojQa(DateTime(2026, 10, 10, 10));
      final envios = EnviosQa(
        hora: reloj.ahora.add(const Duration(hours: 3)),
        escrituraFalla: true,
      );
      await montarQa(tester, remote: remotoQa(), ultimoEnvio: envios, ahora: reloj.call);

      expect(find.text('Podés pedir otro enlace en 60s.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await pasarQa(tester, reloj, const Duration(seconds: 61));
      expect(habilitadoQa(tester, enviarQa), isTrue);
    });

    testWidgets('con la corrección colgada, la lectura de al lado no se traba y la pantalla '
        'funciona', (tester) async {
      final reloj = RelojQa(DateTime(2026, 10, 10, 10));
      final envios = EnviosQa(
        hora: reloj.ahora.add(const Duration(hours: 3)),
        escritura: Completer<void>(),
      );
      await montarQa(tester, remote: remotoQa(), ultimoEnvio: envios, ahora: reloj.call);

      expect(find.text('Podés pedir otro enlace en 60s.'), findsOneWidget);
      expect(await atrasDelSistemaQa(tester), isFalse, reason: 'la pantalla responde y se sale');
    });

    for (final (nombre, hace, queda) in [
      ('justo ahora', Duration.zero, 'Podés pedir otro enlace en 60s.'),
      ('hace 59 s', const Duration(seconds: 59), 'Podés pedir otro enlace en 1s.'),
    ]) {
      testWidgets('guardada $nombre: la espera es la que falta ($queda)', (tester) async {
        final reloj = RelojQa(DateTime(2026, 10, 10, 10));
        final envios = EnviosQa(hora: reloj.ahora.subtract(hace));
        await montarQa(tester, remote: remotoQa(), ultimoEnvio: envios, ahora: reloj.call);
        expect(find.text(queda), findsOneWidget);
        expect(envios.guardados, isEmpty, reason: 'no hace falta corregir una hora pasada');
      });
    }

    testWidgets('guardada hace 60 s justos: sin espera y el botón habilitado', (tester) async {
      final reloj = RelojQa(DateTime(2026, 10, 10, 10));
      final envios = EnviosQa(hora: reloj.ahora.subtract(const Duration(seconds: 60)));
      await montarQa(tester, remote: remotoQa(), ultimoEnvio: envios, ahora: reloj.call);
      expect(esperaQa, findsNothing);
      expect(habilitadoQa(tester, enviarQa), isTrue);
    });
  });

  group('QA #351 · validación del email (los casos de la lista que faltaban)', () {
    for (final (nombre, texto) in [
      ('con un tabulador pegado', 'lucia@correo.com\tana'),
      ('dos correos pegados', 'lucia@correo.com ana@correo.com'),
      ('solo el arroba', '@'),
      ('sin dominio', 'lucia@'),
      ('un texto largo pegado sin arroba', 'x' * 1000),
    ]) {
      testWidgets('$nombre: A03, sin enviar y sin perder lo tipeado', (tester) async {
        final remote = remotoQa();
        await montarQa(tester, remote: remote);
        await escribirQa(tester, texto);
        await tocarQa(tester, enviarQa);
        await tester.pumpAndSettle();

        expect(find.text(incompletoQa), findsOneWidget);
        expect(pedidosQa(remote), 0);
        expect(textoDelCampoQa(tester), isNotEmpty);
        expect(habilitadoQa(tester, enviarQa), isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el largo máximo de un email (254) pasa y 255 no', (tester) async {
      final remote = remotoQa();
      await montarQa(tester, remote: remote);
      const dominio = '@correo.com';
      final en254 = '${'a' * (254 - dominio.length)}$dominio';
      expect(en254.length, 254);
      await escribirQa(tester, '${en254}x');
      await tocarQa(tester, enviarQa);
      await tester.pumpAndSettle();
      expect(find.text(incompletoQa), findsOneWidget, reason: '255 caracteres no es un email');

      await escribirQa(tester, en254);
      await tocarQa(tester, enviarQa);
      await tester.pumpAndSettle();
      expect(find.text(mensajeNeutroQa), findsOneWidget, reason: '254 sí');
    });

    testWidgets('A03 y después el aviso de lectura lenta: el error del campo se va y queda el '
        'aviso, sin las dos cosas a la vez', (tester) async {
      final lectura = Completer<DateTime?>();
      await montarQa(
        tester,
        remote: remotoQa(),
        ultimoEnvio: EnviosQa(lectura: lectura),
      );
      await escribirQa(tester, 'lucia@');
      await tocarQa(tester, enviarQa);
      await tester.pump(topeQa + const Duration(milliseconds: 100));
      expect(find.text(avisoLentaQa), findsOneWidget);
      expect(find.text(incompletoQa), findsNothing);
    });
  });

  group('QA #351 · privacidad', () {
    test('la pantalla no pone el correo con el que arranca en su toString', () {
      const correo = 'ana.perez@correo.com';
      expect(
        const RecuperacionPasswordPage(emailInicial: correo).toString(),
        isNot(contains(correo)),
      );
      expect(
        const RecuperacionPasswordPage(emailInicial: correo).toStringDeep(),
        isNot(contains(correo)),
      );
    });

    // skip: QA #351 — F3 (previo al PR, vista 14): los parámetros de «Enviar enlace de recuperación»
    // llevan el correo en `props` y, a diferencia de los de `ConfirmarRecuperacionPasswordParams`,
    // `ConfirmarPasswordParams` o `IniciarSesionParams`, no apagan `stringify`: en debug, su
    // `toString()` imprime el correo.
    test('los parámetros de pedir el enlace no imprimen el correo en su toString', () {
      const correo = 'ana.perez@correo.com';
      expect(
        const SolicitarRecuperacionPasswordParams(email: correo).toString(),
        isNot(contains(correo)),
      );
    }, skip: true);
  });
}
