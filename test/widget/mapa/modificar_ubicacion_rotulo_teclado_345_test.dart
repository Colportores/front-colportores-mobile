// Vista 07 «Modificar ubicación» (HU-UBI-004), seguimiento #345 de #324 / PR #342: con el teclado
// abierto, el rótulo flotante «EDITAR UBICACIÓN» (07·01) no se dibuja, igual que «Mover el punto».
//
// Por qué: la hoja de abajo crece hasta el 80 % del cuerpo con el teclado y, con el texto a 2× o 3× en un
// 360×640, a la zona del mapa le queda tan poco que el rótulo, partido en dos renglones, quedaba a medio
// tapar (hallazgo 3 del QA de #342; decisión del orquestador del 10/10). Al bajar el teclado vuelve.
//
// Lo que se prueba, con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado):
// - En los tres teléfonos y a 1×, 2× y 3×: con el teclado abierto no hay rótulo, no hay overflow y el
//   mapa llega hasta arriba; sin teclado el rótulo está entero sobre la hoja.
// - El lector de pantalla no tiene el encabezado mientras el teclado está arriba.
// - «MOVER EL PUNTO» (07·02) no se oculta nunca; el rótulo de 07·04 sigue detrás del diálogo.
// - Casos límite: el teclado que sube y baja varias veces, el que baja de a poco, la rotación, volver
//   atrás y reentrar, y la falla a mitad del guardado (el teclado baja y el rótulo vuelve).
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/mapa_base_falso.dart' show VistaMapaFalsa;
import '../../helpers/modificar_ubicacion_qa_307_arnes.dart';

String _x(double escala) => '${escala.round()}×';

final _rotulo = find.text(TextosModificar.tituloEditar);

/// El borde de la hoja (su `Material`).
Finder get _hoja =>
    find.ancestor(of: find.byType(HojaModificarDatos), matching: find.byType(Material)).first;

Finder get _cerrar => find.byTooltip(TextosModificar.cerrar);

void main() {
  setUpAll(cargarFuentesReales);

  final telefonos = <(String, Size, double)>[
    ('360×640', telefono360x640, tecladoAbierto),
    ('412×915', const Size(412, 915), 340),
    ('320×568', telefono320x568, tecladoAbierto),
  ];

  group('#345 · 07·01 · el rótulo «EDITAR UBICACIÓN» con el teclado', () {
    for (final (nombreTel, tamano, teclado) in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        testWidgets(
          '$nombreTel · texto ${_x(escala)} · teclado de ${teclado.round()} dp: abierto no '
          'hay rótulo ni overflow y el mapa llega hasta arriba; al cerrarlo vuelve entero sobre '
          'la hoja',
          (tester) async {
            await abrirEdicion(tester, tamano: tamano, escala: escala);
            expect(_rotulo, findsOneWidget, reason: 'sin teclado el rótulo está');

            await abrirTeclado(tester, alto: teclado);
            await tester.enterText(campoNumero, '1238');
            await asentar(tester);

            expect(_rotulo, findsNothing, reason: 'con el teclado abierto no se dibuja');
            expect(tester.takeException(), isNull, reason: 'sin overflow');
            expect(
              tester.getRect(find.byType(VistaMapaFalsa)).top,
              closeTo(0, .5),
              reason: 'sin rótulo el mapa no baja para dejarle lugar: llega hasta arriba',
            );
            expect(_cerrar, findsOneWidget, reason: '«Cerrar» sigue');
            expect(tester.getRect(_cerrar).top, greaterThanOrEqualTo(0));

            await cerrarTeclado(tester);
            expect(_rotulo, findsOneWidget, reason: 'al cerrar el teclado vuelve');
            final rotulo = tester.getRect(_rotulo);
            final hoja = tester.getRect(_hoja);
            expect(rotulo.bottom, lessThanOrEqualTo(hoja.top + .5), reason: '$rotulo contra $hoja');
            expect(rotulo.top, greaterThanOrEqualTo(0));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('#345 · 07·01 · lector de pantalla', () {
    testWidgets('el encabezado «EDITAR UBICACIÓN» está sin teclado, no está con el teclado abierto '
        'y vuelve al cerrarlo', (tester) async {
      final semantica = tester.ensureSemantics();
      await abrirEdicion(tester, escala: 2);
      final etiqueta = find.bySemanticsLabel(TextosModificar.tituloEditar);
      expect(etiqueta, findsOneWidget);
      expect(tester.getSemantics(etiqueta).flagsCollection.isHeader, isTrue);

      await abrirTeclado(tester);
      expect(etiqueta, findsNothing, reason: 'oculto de la vista, también de la semántica');
      expect(find.bySemanticsLabel(RegExp('EDITAR')), findsNothing);

      await cerrarTeclado(tester);
      expect(etiqueta, findsOneWidget);
      expect(tester.getSemantics(etiqueta).flagsCollection.isHeader, isTrue);
      semantica.dispose();
    });
  });

  group('#345 · 07·02 y 07·04 · los otros rótulos no se tocan', () {
    testWidgets(
      '07·02 «MOVER EL PUNTO» se dibuja siempre: en ese modo no hay campos que escribir',
      (tester) async {
        await abrirEdicion(tester, escala: 2);
        await tester.tap(find.text(TextosModificar.moverElPunto));
        await asentar(tester);
        expect(find.text(TextosModificar.tituloMover), findsOneWidget);
        expect(_rotulo, findsNothing);

        // Aun con un teclado que el sistema dejó arriba, el ajuste del punto lleva su rótulo.
        await abrirTeclado(tester);
        expect(find.text(TextosModificar.tituloMover), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('07·04 «¿Descartar los cambios?»: el rótulo sigue detrás del diálogo (el teclado '
        'está cerrado)', (tester) async {
      await abrirEdicion(tester, escala: 2);
      await tester.enterText(campoNumero, '1238');
      await asentar(tester);
      await tester.tap(_cerrar);
      await asentar(tester);

      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      expect(_rotulo, findsOneWidget);
    });
  });

  group('#345 · 07·01 · casos límite', () {
    testWidgets(
      'el teclado que sube y baja varias veces seguidas, sin esperar a que termine, queda '
      'como el último estado',
      (tester) async {
        await abrirEdicion(tester, escala: 2);
        for (var i = 0; i < 4; i++) {
          ponerTeclado(tester, tecladoAbierto);
          await tester.pump(const Duration(milliseconds: 16));
          ponerTeclado(tester, 0);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await asentar(tester);
        expect(_rotulo, findsOneWidget, reason: 'terminó cerrado');

        ponerTeclado(tester, tecladoAbierto);
        await tester.pump(const Duration(milliseconds: 16));
        ponerTeclado(tester, 0);
        await tester.pump(const Duration(milliseconds: 16));
        ponerTeclado(tester, tecladoAbierto);
        await asentar(tester);
        expect(_rotulo, findsNothing, reason: 'terminó abierto');

        await cerrarTeclado(tester);
        expect(_rotulo, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('el teclado que baja de a poco: no hay rótulo mientras quede un dp de teclado y '
        'aparece al llegar a 0', (tester) async {
      await abrirEdicion(tester, escala: 3);
      await abrirTeclado(tester);
      var cuadros = 0;
      await bajarTecladoDeAPoco(
        tester,
        alCuadro: (_) {
          cuadros++;
          expect(
            _rotulo,
            findsNothing,
            reason: 'con ${tester.view.viewInsets.bottom} dp de teclado no se dibuja',
          );
        },
      );
      expect(cuadros, greaterThan(5), reason: 'bajó de a poco, no de golpe');
      await tester.pump();
      expect(tester.view.viewInsets.bottom, 0);
      expect(_rotulo, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('girado (640×360) con el teclado arriba tampoco hay rótulo; al cerrarlo vuelve', (
      tester,
    ) async {
      await abrirEdicion(tester, tamano: const Size(640, 360), escala: 2);
      await abrirTeclado(tester, alto: 180);
      expect(_rotulo, findsNothing);
      await cerrarTeclado(tester);
      expect(_rotulo, findsOneWidget);
    });

    testWidgets('volver atrás y reentrar: la pantalla nueva arranca con el rótulo y lo pierde con '
        'el teclado otra vez', (tester) async {
      await abrirEdicion(tester, escala: 2);
      await abrirTeclado(tester);
      expect(_rotulo, findsNothing);
      await cerrarTeclado(tester);
      await tester.tap(_cerrar);
      await asentar(tester, 20);
      expect(find.text('abrir'), findsOneWidget, reason: 'volvió a la pantalla de abajo');
      expect(_rotulo, findsNothing);

      await tester.tap(find.text('abrir'));
      await asentar(tester, 20);
      expect(_rotulo, findsOneWidget, reason: 'la pantalla nueva arranca sin teclado');
      await abrirTeclado(tester);
      expect(_rotulo, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'falla a mitad del guardado: baja el teclado, vuelve el rótulo y el aviso queda a la '
      'vista',
      (tester) async {
        final m = await abrirEdicion(tester, escala: 2);
        await tester.enterText(campoNumero, '1238');
        await asentarConTeclado(tester);
        expect(tester.view.viewInsets.bottom, tecladoAbierto, reason: 'el teclado subió');
        expect(_rotulo, findsNothing);

        await fallarPorCambio(tester, m, conTeclado: true);

        expect(
          tester.view.viewInsets.bottom,
          0,
          reason: 'al salir el aviso la hoja baja el teclado',
        );
        expect(_rotulo, findsOneWidget);
        expect(find.textContaining('cambió mientras la editabas'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
