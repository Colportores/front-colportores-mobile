// QA del PR #377 (#335, HU-AUTH-002, vista 12 «Verificá tu cuenta»): «Reenviar en Ns» como relleno del
// botón, igual que el canvas (A03 y A01b).
//
// Lo que `verificacion_cuenta_regresiva_335_test.dart` y `verificacion_email_page_test.dart` no miden:
// - los 13 estados del canvas (A01 a A08, A01b y las variantes de A04) en 5 teléfonos × texto 1,0 y 2,0,
//   sin overflow, con las acciones a la vista y el rótulo entero dentro del botón;
// - lo que se pinta de verdad (píxeles): el relleno #F3F1EA a la izquierda, el crema a la derecha, el
//   borde sin tapar y las esquinas sin que asome el relleno, en píldora y en rectángulo;
// - la altura del botón estable durante los 60 s (un rótulo que pasa a dos renglones a mitad de la
//   cuenta empuja todo lo de arriba) y el barrido del tamaño de letra de 1,0× a 3,0×;
// - el reloj: atrasado o adelantado al volver de segundo plano, correo del alta con hora en el futuro,
//   justo 60 s y 59,5 s, salir a los 59 s y volver pasados los 60;
// - el lector de pantalla: un solo nodo «Reenviar en Ns», el aviso de éxito como única región viva y
//   con el mismo texto durante toda la cuenta, el orden de lectura;
// - la decisión del 16/10 (P1) sobre 12-A04 y 12-A04b: la barra avanza con lo transcurrido, el rótulo
//   en JetBrains Mono y el rótulo apagado a 4,5:1;
// - casos límite: falla a mitad (500), límite (429), teclado abierto, cambio del tamaño de letra con
//   la cuenta corriendo, reentradas.
//
// Las capturas solo con `--dart-define=QA_CAPTURAS=true`, en `.dart_tool/qa_capturas/` (fuera del repo).
import 'dart:async';
import 'dart:math' as math;

import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista12_335_arnes.dart';

String _nombre(Size t, double escala) => '${t.width.toInt()}×${t.height.toInt()} ×$escala';

/// Cuántos nodos del árbol de accesibilidad son región viva.
int _regionesVivas(WidgetTester tester) {
  var n = 0;
  void visitar(SemanticsNode nodo) {
    if (nodo.getSemanticsData().flagsCollection.isLiveRegion) n++;
    nodo.visitChildren((hijo) {
      visitar(hijo);
      return true;
    });
  }

  visitar(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return n;
}

/// Las etiquetas del árbol de accesibilidad, en el orden en que se leen.
List<String> _etiquetas(WidgetTester tester) {
  final etiquetas = <String>[];
  void visitar(SemanticsNode nodo) {
    final datos = nodo.getSemanticsData();
    if (datos.label.isNotEmpty) etiquetas.add(datos.label);
    nodo.visitChildren((hijo) {
      visitar(hijo);
      return true;
    });
  }

  visitar(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return etiquetas;
}

/// El color con que se lee [fg] (con su opacidad) sobre [bg].
Color _sobre(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  // ---------------------------------------------------------------------------------------------
  // 0 · Cobertura del diseño: cada artboard y variante, en 5 teléfonos × 1,0 y 2,0.
  // ---------------------------------------------------------------------------------------------
  group('matriz de estados del canvas 12', () {
    for (final e in Estado12.values) {
      for (final tam in tamanos) {
        for (final escala in escalas) {
          testWidgets('${e.rotulo} a ${_nombre(tam, escala)}: sin overflow, ningún texto cortado y '
              'las acciones a la vista', (tester) async {
            await llegarA(tester, e, tam: tam, escala: escala);

            expect(tester.takeException(), isNull);
            sinTextoCortado(tester);
            for (final b in tester.widgetList<ButtonStyleButton>(find.byType(ButtonStyleButton))) {
              expect(b.child, isNotNull);
            }
            for (final f in find.byType(ButtonStyleButton).evaluate()) {
              final alFinder = find.byWidget(f.widget);
              await tester.ensureVisible(alFinder);
              await tester.pump();
              final r = tester.getRect(alFinder);
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(tam.width));
              expect(r.top, greaterThanOrEqualTo(0));
              expect(r.bottom, lessThanOrEqualTo(tam.height));
            }
            // Capturas: lo de arriba y, con la pantalla desplazada al final, las acciones.
            await capturar(
              tester,
              '${e.id}_${tam.width.toInt()}x${tam.height.toInt()}_x${escala}_a',
            );
            await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -5000));
            await tester.pump();
            await capturar(
              tester,
              '${e.id}_${tam.width.toInt()}x${tam.height.toInt()}_x${escala}_b',
            );
            await cerrarApp(tester);
          });
        }
      }
    }
  });

  // ---------------------------------------------------------------------------------------------
  // 1 · Lo que se pinta de verdad.
  // ---------------------------------------------------------------------------------------------
  group('A03 · píxeles: el relleno es el del canvas y no tapa el borde', () {
    testWidgets('texto normal (píldora): relleno #F3F1EA a la izquierda, crema a la derecha, borde '
        'a la vista y esquina sin relleno', (tester) async {
      await llegarA(tester, Estado12.a03);
      final b = tester.getRect(botonVisual);
      final p = await leerPixeles(tester);

      final dentro = p.en(b.left + 30, b.center.dy);
      final fuera = p.en(b.right - 30, b.center.dy);
      final borde = p.en(b.left + 0.5, b.center.dy);
      expect(mismoColor(dentro, rellenoDelCanvas), isTrue, reason: 'relleno: ${hex(dentro)}');
      // Lo que no se rellenó es el crema de la pantalla, como en el canvas (sin fondo propio).
      expect(mismoColor(fuera, cremaDelCanvas), isTrue, reason: 'sin rellenar: ${hex(fuera)}');
      expect(
        mismoColor(borde, bordeDelBotonApagado, tolerancia: 8),
        isTrue,
        reason: 'borde: ${hex(borde)}',
      );
      expect(mismoColor(borde, rellenoDelCanvas), isFalse, reason: 'el relleno tapó el borde');

      // Un punto fuera de la curva de la píldora y dentro de un rectángulo redondeado de 14,5: ahí no
      // puede asomar el relleno.
      final r = b.height / 2;
      const y = 5.0;
      final dxPildora = r - math.sqrt(r * r - (r - y) * (r - y));
      final dxRect = 1.5 + 14.5 - math.sqrt(14.5 * 14.5 - (14.5 - (y - 1.5)) * (14.5 - (y - 1.5)));
      final esquina = p.en(b.left + (dxPildora + dxRect) / 2, b.top + y);
      expect(
        mismoColor(esquina, rellenoDelCanvas),
        isFalse,
        reason: 'el relleno asoma fuera de la píldora: ${hex(esquina)}',
      );
      await cerrarApp(tester);
    });

    testWidgets(
      'texto grande (rectángulo de radio 16): relleno y borde en su lugar, sin relleno en '
      'la esquina',
      (tester) async {
        await llegarA(tester, Estado12.a03, tam: const Size(360, 640), escala: 2);
        final b = tester.getRect(botonVisual);
        final p = await leerPixeles(tester);

        final dentro = p.en(b.left + 6, b.center.dy);
        final borde = p.en(b.left + 0.5, b.center.dy);
        final esquina = p.en(b.left + 2.2, b.top + 2.2);
        expect(mismoColor(dentro, rellenoDelCanvas), isTrue, reason: 'relleno: ${hex(dentro)}');
        expect(
          mismoColor(borde, bordeDelBotonApagado, tolerancia: 8),
          isTrue,
          reason: 'borde: ${hex(borde)}',
        );
        expect(mismoColor(esquina, rellenoDelCanvas), isFalse, reason: 'esquina: ${hex(esquina)}');
        await cerrarApp(tester);
      },
    );

    testWidgets(
      'el rótulo gris se lee a 4,5:1 sobre lo que se pinta de verdad (relleno y fondo) en '
      'cada punto de la cuenta',
      (tester) async {
        final esc = await llegarA(tester, Estado12.a03, segundos: 0);
        for (var s = 0; s < 60; s += 3) {
          if (s > 0) await esc.reloj.pasar(tester, 3);
          final b = tester.getRect(botonVisual);
          final rotulo = estiloDelRotulo(tester, 'Reenviar en ${60 - s}s').color!;
          final p = await leerPixeles(tester);
          final texto = tester.getRect(find.text('Reenviar en ${60 - s}s'));
          // Fondos a los dos lados del texto, dentro del botón.
          for (final x in [b.left + 14, b.right - 14, texto.left - 4, texto.right + 4]) {
            if (x < b.left + 3 || x > b.right - 3) continue;
            final fondo = p.en(x, b.center.dy);
            expect(
              contraste(rotulo, fondo),
              greaterThanOrEqualTo(4.5),
              reason: 'a los $s s, fondo ${hex(fondo)} en x=${x.toStringAsFixed(1)}',
            );
          }
        }
        await cerrarApp(tester);
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  // 2 · La altura del botón durante la cuenta y el barrido del tamaño de letra.
  // ---------------------------------------------------------------------------------------------
  group('A03 · la altura del botón no salta durante los 60 s', () {
    for (final tam in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 1.5, 2.0, 3.0]) {
        testWidgets('${_nombre(tam, escala)}: el botón mide lo mismo de «Reenviar en 60s» a «1s»', (
          tester,
        ) async {
          final esc = await llegarA(tester, Estado12.a03, tam: tam, escala: escala, segundos: 0);
          final alturas = <int, double>{};
          for (var s = 0; s < 60; s++) {
            if (s > 0) await esc.reloj.pasar(tester, 1);
            alturas[60 - s] = tester.getRect(botonVisual).height;
          }
          final distintas = alturas.values.map((h) => h.toStringAsFixed(1)).toSet();
          expect(
            distintas,
            hasLength(1),
            reason:
                'la altura cambia durante la cuenta: '
                '${alturas.entries.where((e) => e.value != alturas[60]).map((e) => '${e.key}s=${e.value}').take(4).join(', ')}',
          );
          expect(tester.takeException(), isNull);
          await cerrarApp(tester);
        });
      }
    }
  });

  group('la forma de «Reenviar» no cambia al empezar ni al terminar la espera', () {
    for (final escala in const [1.0, 2.0]) {
      testWidgets(
        'texto ×$escala: sin cuenta, con cuenta y con el candado es la misma forma, y con '
        'el texto grande la de «Ya verifiqué mi email»',
        (tester) async {
          ShapeBorder? forma() => tester.widget<Material>(botonVisual).shape;
          final esc = await montar(tester, escala: escala, tam: const Size(360, 640));
          final enReposo = forma();
          final deYaVerifique = tester
              .widget<Material>(
                find.descendant(of: yaVerifique, matching: find.byType(Material)).first,
              )
              .shape;

          await tocarReenviar(tester);
          expect(forma(), enReposo, reason: 'al empezar la espera (A02)');
          await esc.reloj.pasar(tester, 18);
          expect(forma(), enReposo, reason: 'con la cuenta corriendo (A03)');
          await esc.reloj.pasar(tester, 42);
          expect(forma(), enReposo, reason: 'al terminar la espera (A01)');
          if (escala * 14 > 20) {
            expect(
              (enReposo! as RoundedRectangleBorder).borderRadius,
              (deYaVerifique! as RoundedRectangleBorder).borderRadius,
            );
          }
          await cerrarApp(tester);

          await llegarA(tester, Estado12.a06, escala: escala, tam: const Size(360, 640));
          expect(forma(), enReposo, reason: 'con el candado puesto (A06)');
          await cerrarApp(tester);
        },
      );
    }
  });

  group('A03 · barrido del tamaño de letra de 1,0× a 3,0×', () {
    for (final tam in const [Size(320, 568), Size(360, 640)]) {
      for (final escala in const [1.0, 1.25, 1.4, 1.45, 1.5, 1.75, 2.0, 2.5, 3.0]) {
        testWidgets(
          '${_nombre(tam, escala)}: rótulo entero en el botón, forma ${escala * 14 > 20 ? 'rectángulo' : 'píldora'} y relleno al 30 %',
          (tester) async {
            await llegarA(tester, Estado12.a03, tam: tam, escala: escala);

            expect(tester.takeException(), isNull);
            rotuloDentroDelBoton(tester, 'Reenviar en 42s');
            final forma = tester.widget<Material>(botonVisual).shape;
            if (escala * 14 > 20) {
              expect(forma, isA<RoundedRectangleBorder>());
            } else {
              expect(forma, isA<StadiumBorder>());
            }
            final b = tester.getRect(botonVisual);
            final r = tester.getRect(relleno);
            expect(r.width, closeTo((b.width - 3) * 0.3, 0.05));
            expect(r.height, closeTo(b.height - 3, 0.05));
            await cerrarApp(tester);
          },
        );
      }
    }

    testWidgets('el recorte del relleno es una píldora con el texto normal y un rectángulo con el '
        'texto grande (la forma de adentro sigue a la de afuera)', (tester) async {
      await llegarA(tester, Estado12.a03);
      final clipper = tester.widget<ClipPath>(
        find.descendant(of: boton, matching: find.byType(ClipPath)),
      );
      expect((clipper.clipper! as ShapeBorderClipper).shape, isA<StadiumBorder>());
      await cerrarApp(tester);

      await llegarA(tester, Estado12.a03, escala: 2);
      final grande = tester.widget<ClipPath>(
        find.descendant(of: boton, matching: find.byType(ClipPath)),
      );
      expect((grande.clipper! as ShapeBorderClipper).shape, isA<RoundedRectangleBorder>());
      await cerrarApp(tester);
    });

    testWidgets('cambiar el tamaño de letra con la cuenta corriendo cambia la forma y el relleno '
        'sigue en el mismo punto', (tester) async {
      final esc = await llegarA(tester, Estado12.a03, tam: const Size(360, 640));
      expect(tester.widget<Material>(botonVisual).shape, isA<StadiumBorder>());

      esc.escala.value = 2;
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Reenviar en 42s'), findsOneWidget);
      expect(transcurrido(tester), closeTo(0.3, 1e-9));
      expect(tester.widget<Material>(botonVisual).shape, isA<RoundedRectangleBorder>());
      await esc.reloj.pasar(tester, 2);
      expect(find.text('Reenviar en 40s'), findsOneWidget);

      esc.escala.value = 1;
      await tester.pump();
      expect(tester.widget<Material>(botonVisual).shape, isA<StadiumBorder>());
      await cerrarApp(tester);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 3 · El reloj.
  // ---------------------------------------------------------------------------------------------
  group('el reloj de la cuenta regresiva', () {
    testWidgets('al volver de segundo plano con el reloj 10 minutos atrasado, la cuenta recomienza '
        'como mucho en 60 s (nunca más) y termina', (tester) async {
      final esc = await llegarA(tester, Estado12.a03);
      expect(find.text('Reenviar en 42s'), findsOneWidget);

      esc.reloj.ahora = esc.reloj.ahora.subtract(const Duration(minutes: 10));
      await irAlFondoYVolver(tester);

      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(transcurrido(tester), 0);
      expect(habilitado(tester), isFalse);
      await esc.reloj.pasar(tester, 60);
      expect(find.text('Reenviar email'), findsOneWidget);
      expect(habilitado(tester), isTrue);
      expect(relleno, findsNothing);
      await cerrarApp(tester);
    });

    testWidgets('al volver de segundo plano con el reloj 10 minutos adelantado, el botón queda '
        'habilitado y sin relleno', (tester) async {
      final esc = await llegarA(tester, Estado12.a03);

      esc.reloj.ahora = esc.reloj.ahora.add(const Duration(minutes: 10));
      await irAlFondoYVolver(tester);

      expect(find.text('Reenviar email'), findsOneWidget);
      expect(habilitado(tester), isTrue);
      expect(relleno, findsNothing);
      expect(mensajeReenvio, findsNothing);
      await cerrarApp(tester);
    });

    testWidgets('con el reloj adelantado y la app al frente, la cuenta sigue su tic y llega a cero '
        'sin romperse', (tester) async {
      final esc = await llegarA(tester, Estado12.a03);

      esc.reloj.ahora = esc.reloj.ahora.add(const Duration(hours: 5));
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.text('Reenviar en 41s'), findsOneWidget);
      for (var i = 0; i < 41; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Reenviar email'), findsOneWidget);
      expect(habilitado(tester), isTrue);
      await cerrarApp(tester);
    });

    testWidgets('el correo del alta con hora en el futuro (reloj atrasado al entrar): «Reenviar en '
        '60s» y relleno en cero, nunca más de 60 s', (tester) async {
      final esc = await montar(tester, envioDelAlta: base.add(const Duration(minutes: 5)));

      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(transcurrido(tester), 0);
      await esc.reloj.pasar(tester, 60);
      expect(find.text('Reenviar email'), findsOneWidget);
      expect(habilitado(tester), isTrue);
      await cerrarApp(tester);
    });

    testWidgets('el correo del alta salió hace exactamente 60 s: sin cuenta ni relleno', (
      tester,
    ) async {
      await montar(tester, envioDelAlta: base.subtract(const Duration(seconds: 60)));

      expect(find.text('Reenviar email'), findsOneWidget);
      expect(habilitado(tester), isTrue);
      expect(relleno, findsNothing);
      expect(mensajeReenvio, findsNothing);
      await cerrarApp(tester);
    });

    testWidgets(
      'el correo del alta salió hace 59,5 s: «Reenviar en 1s» con el relleno casi lleno y '
      'al segundo se habilita',
      (tester) async {
        final esc = await montar(
          tester,
          envioDelAlta: base.subtract(const Duration(milliseconds: 59500)),
        );

        expect(find.text('Reenviar en 1s'), findsOneWidget);
        expect(transcurrido(tester), closeTo(59 / 60, 1e-9));
        await esc.reloj.pasar(tester, 1);
        expect(find.text('Reenviar email'), findsOneWidget);
        expect(habilitado(tester), isTrue);
        await cerrarApp(tester);
      },
    );

    testWidgets('salir a los 59 s y volver pasados los 60: sin cuenta, habilitado y sin ningún '
        'Timer vivo', (tester) async {
      final bloqueos = BloqueoReenvioVerificacionEnMemoria();
      final esc = await montar(tester, bloqueos: bloqueos);
      await tocarReenviar(tester);
      await esc.reloj.pasar(tester, 59);
      expect(find.text('Reenviar en 1s'), findsOneWidget);
      await cerrarApp(tester);

      final reloj = esc.reloj..ahora = esc.reloj.ahora.add(const Duration(seconds: 2));
      await montar(tester, reloj: reloj, bloqueos: bloqueos);

      expect(find.text('Reenviar email'), findsOneWidget);
      expect(habilitado(tester), isTrue);
      expect(relleno, findsNothing);
      await cerrarApp(tester);
    });

    testWidgets('volver de segundo plano varias veces seguidas no duplica el tic ni acelera la '
        'cuenta', (tester) async {
      final esc = await llegarA(tester, Estado12.a03);
      for (var i = 0; i < 4; i++) {
        await irAlFondoYVolver(tester);
      }
      expect(find.text('Reenviar en 42s'), findsOneWidget);

      await esc.reloj.pasar(tester, 10);

      expect(find.text('Reenviar en 32s'), findsOneWidget);
      expect(transcurrido(tester), closeTo(28 / 60, 1e-9));
      await cerrarApp(tester);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 4 · El lector de pantalla.
  // ---------------------------------------------------------------------------------------------
  group('el lector de pantalla y la cuenta regresiva', () {
    testWidgets(
      'A03: un solo nodo «Reenviar en Ns», apagado, sin valor ni región viva, y el relleno '
      'no aparece en el árbol',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await llegarA(tester, Estado12.a03);

        expect(find.semantics.byLabel(RegExp('^Reenviar')), findsOneWidget);
        final datos = tester.getSemantics(boton).getSemanticsData();
        expect(datos.label, 'Reenviar en 42s');
        expect(datos.value, isEmpty);
        expect(
          tester.getSemantics(boton),
          isSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            isLiveRegion: false,
            hasTapAction: false,
          ),
        );
        expect(datos.hasAction(SemanticsAction.increase), isFalse);
        semantica.dispose();
        await cerrarApp(tester);
      },
    );

    testWidgets('A03: el orden de lectura es el del canvas y no hay nodos de más por el relleno', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegarA(tester, Estado12.a03);

      final etiquetas = _etiquetas(tester);
      final iVerifique = etiquetas.indexOf('Ya verifiqué mi email');
      final iReenviar = etiquetas.indexOf('Reenviar en 42s');
      final iVolver = etiquetas.indexOf('Volver al login');
      expect(iVerifique, isNonNegative);
      expect(iReenviar, greaterThan(iVerifique));
      expect(iVolver, greaterThan(iReenviar));
      expect(etiquetas.where((e) => e.contains('Reenviar en')), hasLength(1));
      semantica.dispose();
      await cerrarApp(tester);
    });

    testWidgets('el aviso de éxito es la única región viva y dice lo mismo en los 60 s: nada se '
        'vuelve a anunciar segundo a segundo', (tester) async {
      final semantica = tester.ensureSemantics();
      final esc = await llegarA(tester, Estado12.a02, segundos: 0);
      expect(_regionesVivas(tester), 1);
      tester.takeAnnouncements();

      final textos = <String>{};
      for (var s = 1; s < 60; s++) {
        await esc.reloj.pasar(tester, 1);
        textos.add(tester.getSemantics(mensajeReenvio).getSemanticsData().label);
        expect(_regionesVivas(tester), 1, reason: 'a los $s s');
      }

      expect(textos, {'Te reenviamos el correo. Puede tardar unos minutos.'});
      expect(tester.takeAnnouncements(), isEmpty);
      semantica.dispose();
      await cerrarApp(tester);
    });

    testWidgets('A01b (después del alta): sin aviso ni región viva, y el botón dice la cuenta', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegarA(tester, Estado12.a01b);

      expect(_regionesVivas(tester), 0);
      expect(find.semantics.byLabel('Reenviar en 48s'), findsOneWidget);
      semantica.dispose();
      await cerrarApp(tester);
    });

    testWidgets('al llegar a cero el botón vuelve a ser «Reenviar email», habilitado, y con él el '
        'nodo cambia de etiqueta y de estado', (tester) async {
      final semantica = tester.ensureSemantics();
      final esc = await llegarA(tester, Estado12.a03, segundos: 0);

      await esc.reloj.pasar(tester, 60);

      final datos = tester.getSemantics(boton).getSemanticsData();
      expect(datos.label, 'Reenviar email');
      expect(
        tester.getSemantics(boton),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true),
      );
      semantica.dispose();
      await cerrarApp(tester);
    });
  });

  // ---------------------------------------------------------------------------------------------
  // 5 · Decisión del 16/10 (P1): la cuenta del botón primario de 12-A04 y 12-A04b.
  // ---------------------------------------------------------------------------------------------
  group('12-A04 y 12-A04b · la cuenta del primario (decisión del 16/10, P1)', () {
    for (final e in [Estado12.a04Cuenta, Estado12.a04bCuenta, Estado12.inutilCuenta]) {
      group(e.rotulo, () {
        testWidgets('la barra de 3 px avanza con lo transcurrido, como el relleno de A03', (
          tester,
        ) async {
          final esc = await llegarA(tester, e, segundos: 0);
          var anterior = -1.0;
          for (var s = 0; s < 60; s++) {
            if (s > 0) await esc.reloj.pasar(tester, 1);
            final valor = tester.widget<LinearProgressIndicator>(barra).value!;
            expect(
              valor,
              closeTo(s / 60, 1e-9),
              reason: 'a los $s s la barra tiene que valer $s/60',
            );
            expect(valor, greaterThan(anterior));
            anterior = valor;
          }
          await cerrarApp(tester);
        });

        testWidgets(
          'el rótulo «Reenviar en Ns» va en JetBrains Mono, como en el resto de la cuenta',
          (tester) async {
            await llegarA(tester, e);

            expect(estiloDelRotulo(tester, 'Reenviar en 42s').fontFamily, 'JetBrainsMono');
            await cerrarApp(tester);
          },
        );

        testWidgets(
          'el rótulo apagado llega a 4,5:1 sobre lo que se pinta de verdad, y el botón se '
          'sigue viendo apagado (no es el navy del activo)',
          (tester) async {
            final esc = await llegarA(tester, e, segundos: 0);
            for (var s = 0; s < 60; s += 6) {
              if (s > 0) await esc.reloj.pasar(tester, 6);
              final b = tester.getRect(botonVisual);
              final p = await leerPixeles(tester);
              final fondo = p.en(b.left + 14, b.center.dy);
              final fondoDerecha = p.en(b.right - 14, b.center.dy);
              final color = estiloDelRotulo(tester, 'Reenviar en ${60 - s}s').color!;
              expect(
                contraste(_sobre(color, fondo), fondo),
                greaterThanOrEqualTo(4.5),
                reason: 'a los $s s: rótulo ${hex(_sobre(color, fondo))} sobre ${hex(fondo)}',
              );
              expect(
                contraste(_sobre(color, fondoDerecha), fondoDerecha),
                greaterThanOrEqualTo(4.5),
                reason: 'a los $s s: rótulo sobre ${hex(fondoDerecha)}',
              );
              expect(
                mismoColor(fondo, navyDelCanvas, tolerancia: 24),
                isFalse,
                reason: 'se ve como el botón activo: ${hex(fondo)}',
              );
            }
            await cerrarApp(tester);
          },
        );

        // El contraste del rótulo lo mide el test de arriba, por píxeles: la guía de Flutter con las
        // fuentes reales se confunde (ver `qa_vista12_cuenta_regresiva_335_contraste_test.dart`).
        testWidgets(
          'con la cuenta corriendo, a 390×844 ×1 y 360×640 ×2: toque de 48 dp y etiquetas',
          (tester) async {
            for (final (tam, escala) in [
              (const Size(390, 844), 1.0),
              (const Size(360, 640), 2.0),
            ]) {
              final semantica = tester.ensureSemantics();
              await llegarA(tester, e, tam: tam, escala: escala);

              expect(tester.takeException(), isNull);
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              semantica.dispose();
              await cerrarApp(tester);
            }
          },
        );
      });
    }
  });

  group('12-A04 · la barra de 3 px', () {
    // skip: QA #335 — el relleno de la barra (#002856) y su pista (#13407A, el `secondaryContainer`
    // del tema) dan 1,42:1: el avance no se ve. Con `backgroundColor: colores.borde` (#E3E7EE) da más
    // de 10:1.
    testWidgets(
      'el avance se ve: el relleno de la barra se distingue de su pista (3:1)',
      skip: true,
      (tester) async {
        await llegarA(tester, Estado12.a04Cuenta);
        final r = tester.getRect(barra);
        final p = await leerPixeles(tester);
        final lleno = p.en(r.left + r.width * 0.1, r.center.dy);
        final pista = p.en(r.left + r.width * 0.9, r.center.dy);

        expect(
          contraste(lleno, pista),
          greaterThanOrEqualTo(3),
          reason: 'relleno ${hex(lleno)} sobre pista ${hex(pista)}',
        );
        await cerrarApp(tester);
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  // 5b · El otro botón apagado de la vista: el candado de 12-A06.
  // ---------------------------------------------------------------------------------------------
  group('12-A06 · el botón con candado', () {
    // skip: QA #335 — el rótulo del botón con candado se pinta con el 38 % de Material (#A3A8AE sobre
    // #FFFFFF, 2,4:1); el canvas lo dibuja en #5B6B82 y el de la cuenta (A02/A03) ya llega a 4,8:1.
    testWidgets(
      'el rótulo «Reenviar email» apagado se lee a 4,5:1, como el de la cuenta',
      skip: true,
      (tester) async {
        await llegarA(tester, Estado12.a06);
        final b = tester.getRect(botonVisual);
        final p = await leerPixeles(tester);
        final fondo = p.en(b.left + 14, b.center.dy);
        final color = estiloDelRotulo(tester, 'Reenviar email').color!;

        expect(
          contraste(_sobre(color, fondo), fondo),
          greaterThanOrEqualTo(4.5),
          reason: 'rótulo ${hex(_sobre(color, fondo))} sobre ${hex(fondo)}',
        );
        await cerrarApp(tester);
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  // 6 · Casos límite del flujo de reenvío.
  // ---------------------------------------------------------------------------------------------
  group('casos límite del reenvío con la cuenta', () {
    testWidgets(
      'falla del servidor (500) a mitad del reenvío: aviso con qué hacer, botón habilitado, '
      'sin relleno ni cuenta, y el reintento arranca la cuenta',
      (tester) async {
        final remoto = remotoSano()..fallaAlReenviar = const ServidorException(status: 500);
        final esc = await montar(tester, remoto: remoto);

        await tocarReenviar(tester);

        expect(find.text('Reenviar email'), findsOneWidget);
        expect(habilitado(tester), isTrue);
        expect(relleno, findsNothing);
        expect(
          find.text('No pudimos reenviar el email. Probá de nuevo en unos minutos.'),
          findsOneWidget,
        );
        remoto.fallaAlReenviar = null;
        await tocarReenviar(tester);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(errorGeneral, findsNothing);
        await esc.reloj.pasar(tester, 6);
        expect(transcurrido(tester), closeTo(0.1, 1e-9));
        await cerrarApp(tester);
      },
    );

    testWidgets('límite de reenvíos (429): el botón queda con su candado, sin relleno ni cuenta', (
      tester,
    ) async {
      final remoto = remotoSano()..fallaAlReenviar = const ServidorException(status: 429);
      await montar(tester, remoto: remoto);

      await tocarReenviar(tester);

      expect(avisoLimite, findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Reenviar email'), findsOneWidget);
      expect(habilitado(tester), isFalse);
      expect(relleno, findsNothing);
      expect(barra, findsNothing);
      await cerrarApp(tester);
    });

    testWidgets('volver de segundo plano con el reenvío en vuelo no deja nada trabado', (
      tester,
    ) async {
      final remoto = remotoSano()..demoraReenvio = Completer<void>();
      await montar(tester, remoto: remoto);
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      await tester.pump();

      await irAlFondoYVolver(tester);
      remoto.demoraReenvio!.complete();
      await tester.pumpAndSettle();

      expect(remoto.reenviosPorEmail[lucia], 1);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(mensajeReenvio, findsOneWidget);
      await cerrarApp(tester);
    });

    testWidgets('entrar y salir de la pantalla cinco veces con la cuenta a medias: la cuenta sigue '
        'donde estaba y no queda un Timer de más', (tester) async {
      final bloqueos = BloqueoReenvioVerificacionEnMemoria();
      final esc = await montar(tester, bloqueos: bloqueos);
      await tocarReenviar(tester);
      await esc.reloj.pasar(tester, 5);
      await cerrarApp(tester);

      for (var i = 0; i < 5; i++) {
        esc.reloj.ahora = esc.reloj.ahora.add(const Duration(seconds: 3));
        await montar(tester, reloj: esc.reloj, bloqueos: bloqueos);
        expect(find.text('Reenviar en ${60 - 5 - 3 * (i + 1)}s'), findsOneWidget);
        await cerrarApp(tester);
      }
    });

    testWidgets('A04b con el teclado abierto a 360×640 y texto ×2: el campo y el botón se pueden '
        'alcanzar y no hay overflow', (tester) async {
      await llegarA(
        tester,
        Estado12.a04bCuenta,
        tam: const Size(360, 640),
        escala: 2,
        teclado: 280,
      );

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(boton);
      await tester.pump();
      expect(tester.getRect(boton).bottom, lessThanOrEqualTo(640 - 280));
      await tester.ensureVisible(campo);
      await tester.pump();
      expect(tester.getRect(campo).bottom, lessThanOrEqualTo(640 - 280));
      await cerrarApp(tester);
    });

    testWidgets('A04b: lo tipeado no se pierde al empezar la cuenta ni al terminarla', (
      tester,
    ) async {
      final esc = await llegarA(tester, Estado12.a04bCuenta, segundos: 0);
      expect(tester.widget<TextField>(campo).controller!.text, lucia);

      await esc.reloj.pasar(tester, 60);

      expect(tester.widget<TextField>(campo).controller!.text, lucia);
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
      expect(habilitado(tester), isTrue);
      await cerrarApp(tester);
    });
  });
}
