// QA del paso «¿Con quién?» de la vista 39 (R·04 y C·07, #449, PR #463): lo que la suite del
// implementador no mide. Matriz de tamaños (360×640 y 412×915) × texto (1,0 y 2,0) en los ocho
// estados alcanzables con fuentes reales; validación de entradas (espacios, emoji, pegado largo,
// caracteres especiales); acciones superpuestas; barrera de la hoja; anuncios; privacidad.
//
// Las guías de accesibilidad van en `qa_vista39_con_quien_449_guias_test.dart` (el contraste necesita
// la fuente de prueba: con las reales da falsos negativos).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/services/validador_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_baja_205_arnes.dart'
    show cargarFuentes205, contraste205, expectSinTextoFueraDeLosCostados205;
import '../../helpers/qa_vista39_449_arnes.dart';
import 'hoja_con_quien_arnes.dart';
import 'personas_arnes.dart';

void main() {
  group('matriz de tamaños y escalas, fuentes reales', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado449.values) {
          testWidgets('${estado.name} · ${sufijo449(tamano, escala)}: sin overflow, nada cortado, '
              'la acción principal se alcanza', (tester) async {
            await cargarFuentes205(tester);
            await llegarA449(tester, estado, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados205(tester, tamano);
            await capturar449(tester, '${estado.name}_${sufijo449(tamano, escala)}');

            final accion = switch (estado) {
              Estado449.errorDeLectura => find.widgetWithText(FilledButton, 'Reintentar'),
              Estado449.cargando => botonVolver449,
              Estado449.r04Guardando => find.text('Guardando…'),
              _ => botonEmpezar449,
            };
            expect(accion, findsOneWidget);
            await tester.ensureVisible(accion);
            await tester.pump();
            final r = tester.getRect(accion);
            if (estado != Estado449.r04Guardando) expect(r.height, greaterThanOrEqualTo(48));
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(tamano.width));
            expect(r.bottom, lessThanOrEqualTo(tamano.height));
            expect(r.top, greaterThanOrEqualTo(0));
          });
        }
      }
    }
  });

  group('R·04 · teclado abierto en el teléfono chico', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        '360×640 con el teclado de 280 dp al ${(escala * 100).round()} %: el campo con foco '
        'y «Empezar entrevista» quedan por encima del teclado',
        (tester) async {
          await cargarFuentes205(tester);
          await montar449(tester, tamano: t360x640, escala: escala, teclado: 280);
          tester.testTextInput.register();
          await tester.showKeyboard(campoNombre449);
          await asentar(tester);
          expect(tester.takeException(), isNull);

          const libre = 640 - 280.0;
          expect(tester.getRect(campoNombre449).bottom, lessThanOrEqualTo(libre));
          await tester.ensureVisible(botonEmpezar449);
          await tester.pump();
          expect(tester.getRect(botonEmpezar449).bottom, lessThanOrEqualTo(libre));
          await capturar449(tester, 'r04_teclado_x$escala');
        },
      );
    }
  });

  group('R·04 · validación de entradas', () {
    testWidgets('solo espacios: no guarda y dice qué falta', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montar449(tester, repo: repo);
      await tester.enterText(campoNombre449, '      ');
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      expect(repo.recibidas, isEmpty);
      expect(find.text(ValidadorPersona.mensajeNombre(ProblemaNombre.vacio)), findsOneWidget);
    });

    testWidgets('un solo emoji (1 carácter): no alcanza; dos emoji sí', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montar449(tester, repo: repo);
      await tester.enterText(campoNombre449, '🙂');
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(repo.recibidas, isEmpty);
      expect(find.text(ValidadorPersona.mensajeNombre(ProblemaNombre.corto)), findsOneWidget);

      await tester.enterText(campoNombre449, '🙂🙂');
      await tester.pump();
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(repo.recibidas, hasLength(1));
      expect(repo.recibidas.single.persona.nombre, '🙂🙂');
    });

    testWidgets('espacios de más en los bordes y adentro se limpian al guardar', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montar449(tester, repo: repo);
      await tester.enterText(campoNombre449, '  Ana    María ');
      await tester.enterText(campoApellido449, '     ');
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      expect(repo.recibidas.single.persona.nombre, 'Ana María');
      expect(repo.recibidas.single.persona.apellido, '');
    });

    for (final nombre in [
      "O'Brien-Núñez",
      'Ñandú Çelik',
      '<b>x</b>',
      "x'; DROP TABLE persona;--",
    ]) {
      testWidgets('caracteres especiales «$nombre»: se guardan tal cual', (tester) async {
        final repo = PersonaRepositorioFalso();
        await montar449(tester, repo: repo);
        await tester.enterText(campoNombre449, nombre);
        await tester.pump();
        await tester.ensureVisible(botonEmpezar449);
        await tester.tap(botonEmpezar449);
        await asentar(tester);

        expect(repo.recibidas.single.persona.nombre, nombre.length > 60 ? isNotEmpty : nombre);
      });
    }

    testWidgets('texto pegado de 5000 letras: el campo corta a 60 y se guarda eso', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montar449(tester, repo: repo);
      await tester.enterText(campoNombre449, 'ñ' * 5000);
      await tester.enterText(campoApellido449, 'x' * 5000);
      await tester.pump();

      expect(tester.widget<TextField>(campoNombre449).controller!.text.length, 60);
      expect(tester.widget<TextField>(campoApellido449).controller!.text.length, 60);
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(repo.recibidas.single.persona.nombre.length, 60);
    });

    testWidgets('100 emoji pegados: corta a 60 caracteres sin partir ninguno', (tester) async {
      await montar449(tester);
      await tester.enterText(campoNombre449, '🙂' * 100);
      await tester.pump();

      final texto = tester.widget<TextField>(campoNombre449).controller!.text;
      expect(texto.characters.length, 60);
      expect(texto.runes.every((r) => r == 0x1F642), isTrue, reason: 'ningún emoji partido');
    });

    testWidgets('pegado con salto de línea: el nombre no lleva el salto', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montar449(tester, repo: repo);
      await tester.enterText(campoNombre449, 'Ana\nGómez');
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      expect(repo.recibidas.single.persona.nombre.contains('\n'), isFalse);
    });

    testWidgets('el teclado: «Siguiente» pasa al apellido y «Listo» guarda una sola vez', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montar449(tester, repo: repo);
      tester.testTextInput.register();
      await tester.showKeyboard(campoNombre449);
      await tester.enterText(campoNombre449, 'Pedro');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(tester.widget<TextField>(campoApellido449).focusNode!.hasFocus, isTrue);

      await tester.enterText(campoApellido449, 'Gómez');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await asentar(tester);
      expect(repo.recibidas, hasLength(1));
    });

    testWidgets('«Listo» con el nombre vacío no guarda y lleva el foco al nombre', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montar449(tester, repo: repo);
      tester.testTextInput.register();
      await tester.showKeyboard(campoApellido449);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await asentar(tester);

      expect(repo.recibidas, isEmpty);
      expect(tester.widget<TextField>(campoNombre449).focusNode!.hasFocus, isTrue);
    });
  });

  group('R·04 · avisos y anuncios', () {
    testWidgets('el error del nombre se anuncia al lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      await montar449(tester);
      tester.takeAnnouncements();
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      expect(tester.takeAnnouncements().map((a) => a.message), [
        ValidadorPersona.mensajeNombre(ProblemaNombre.vacio),
      ]);
      handle.dispose();
    });

    testWidgets('la falla de guardado es una región viva (el lector la dice sola)', (tester) async {
      final handle = tester.ensureSemantics();
      await llegarA449(tester, Estado449.r04Falla);

      final aviso = find.bySemanticsLabel(RegExp('No pudimos guardar a la persona'));
      expect(aviso, findsWidgets);
      expect(tester.getSemantics(aviso.first), isSemantics(isLiveRegion: true));
      handle.dispose();
    });

    testWidgets('«Guardando…» no deja la acción ni «Volver» tocables y la falla los devuelve', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      final repo = PersonaRepositorioFalso(compuerta: compuerta, resultados: [fallaDeGuardado]);
      await montar449(tester, repo: repo);
      await tester.enterText(campoNombre449, 'Pedro');
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(find.text('Guardando…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(botonVolver449).onPressed, isNull);

      compuerta.complete();
      await asentar(tester);
      expect(find.text('Guardando…'), findsNothing);
      expect(tester.widget<OutlinedButton>(botonVolver449).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(botonEmpezar449).onPressed, isNotNull);
    });
  });

  group('acciones superpuestas y salidas', () {
    testWidgets('R·04 guardando: tocar afuera de la hoja (la barrera) no la cierra', (
      tester,
    ) async {
      final resultado = await llegarA449(tester, Estado449.r04Guardando);

      await tester.tapAt(const Offset(200, 10));
      await asentar(tester);

      expect(find.byType(HojaConQuien), findsOneWidget);
      expect(resultado.cierres, 0);
    });

    testWidgets('R·04 sin guardar: tocar afuera cierra sin persona', (tester) async {
      final resultado = await montar449(tester);

      await tester.tapAt(const Offset(200, 10));
      await asentar(tester);

      expect(find.byType(HojaConQuien), findsNothing);
      expect(resultado.cierres, 1);
      expect(resultado.elegida, isNull);
    });

    testWidgets('C·07: tocar afuera cierra sin persona', (tester) async {
      final resultado = await llegarA449(tester, Estado449.c07);

      await tester.tapAt(const Offset(200, 10));
      await asentar(tester);

      expect(find.byType(HojaConQuien), findsNothing);
      expect(resultado.cierres, 1);
      expect(resultado.elegida, isNull);
    });

    // QA #449 — un segundo toque en el disparador durante la lectura previa no abre dos hojas.
    testWidgets(
      'un segundo toque en «abrir» mientras la primera lectura todavía no terminó no abre '
      'dos hojas',
      (tester) async {
        final repo = PersonaRepositorioLento(const Duration(milliseconds: 120))
          ..sembrar(personasDeLaCasa(2));
        final resultado = await montar449(tester, repo: repo, abrir: false);

        await tester.tap(find.text('abrir paso'));
        await tester.pump(const Duration(milliseconds: 30));
        await tester.tap(find.text('abrir paso'));
        await asentar(tester, 20);

        expect(find.byType(HojaConQuien), findsOneWidget);
        expect(resultado.abiertas, 1);
      },
    );

    testWidgets('dos veces «Volver» seguidas en C·07: un solo cierre', (tester) async {
      final resultado = await llegarA449(tester, Estado449.c07);

      await tester.tap(botonVolver449);
      await tester.tap(botonVolver449, warnIfMissed: false);
      await asentar(tester);

      expect(resultado.cierres, 1);
    });

    testWidgets('tres aperturas seguidas (con una falla en la primera) no dejan nada trabado', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso(resultados: [fallaDeGuardado]);
      final resultado = await montar449(tester, repo: repo, abrir: false);

      for (var i = 0; i < 3; i++) {
        await abrirPaso(tester);
        if (find.byType(HojaConQuien).evaluate().isEmpty) continue; // una sola persona: se saltó
        await tester.enterText(campoNombre449, 'Pedro$i');
        await tester.ensureVisible(botonEmpezar449);
        await tester.tap(botonEmpezar449);
        await asentar(tester);
        if (find.byType(HojaConQuien).evaluate().isNotEmpty) {
          expect(tester.widget<FilledButton>(botonEmpezar449).onPressed, isNotNull);
          await tester.ensureVisible(botonVolver449);
          await tester.tap(botonVolver449);
          await asentar(tester);
        }
        expect(find.byType(HojaConQuien), findsNothing, reason: 'vuelta $i');
      }
      expect(resultado.cierres, 3);
    });

    testWidgets(
      'lectura que falla siempre: «Reintentar» y «Volver» quedan a mano tras cada intento',
      (tester) async {
        final repo = PersonaRepositorioQueFallaN(999);
        final resultado = await montar449(tester, repo: repo);
        final reintentar = find.widgetWithText(FilledButton, 'Reintentar');

        for (var i = 0; i < 3; i++) {
          expect(reintentar, findsOneWidget, reason: 'intento $i');
          await tester.tap(reintentar);
          await asentar(tester, 30);
        }
        expect(reintentar, findsOneWidget);
        await tester.tap(botonVolver449);
        await asentar(tester);
        expect(resultado.cierres, 1);
        expect(resultado.elegida, isNull);
      },
    );
  });

  group('privacidad', () {
    testWidgets('lo que devuelve el paso lleva solo ids: su texto no trae el nombre', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montar449(tester, repo: repo);
      await tester.enterText(campoNombre449, 'Pedro');
      await tester.enterText(campoApellido449, 'Gómez');
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      final texto = resultado.elegida.toString();
      expect(texto.contains('Pedro'), isFalse);
      expect(texto.contains('Gómez'), isFalse);
    });

    testWidgets('el aviso de privacidad (candado) está siempre en R·04', (tester) async {
      await montar449(tester);
      expect(
        find.text('Estos datos solo viven en tu celular. Nunca se suben a la nube.'),
        findsOneWidget,
      );
    });
  });

  group('contraste del saldo (cálculo)', () {
    test('gris de apoyo sobre la fila elegida (#F2F6FB) y sobre blanco: AA', () {
      const gris = Color(0xFF5B6B82);
      expect(contraste205(gris, const Color(0xFFF2F6FB)), greaterThanOrEqualTo(4.5));
      expect(contraste205(gris, Colors.white), greaterThanOrEqualTo(4.5));
    });
  });
}
