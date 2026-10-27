// QA del centro de notificaciones (#156, PR #481, vista 24 grupo C): lo que los tests del
// implementador no recorren. Los siete estados del canvas a 360x640 y 412x915 con texto 1.0 y 2.0
// (sin desborde, con lo importante a la vista), los escenarios literales de la HU con sus números
// (5 en la semana, 30 viejas), textos largos/emoji, 300 avisos, acciones superpuestas y fallas a
// mitad. Los hallazgos van como `skip` (se corren con `--dart-define=QA_HALLAZGOS=true`).
import 'dart:async';

import 'package:colportores_mobile/features/notificaciones/presentation/widgets/textos_centro_notificaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';
import '../helpers/qa_centro_notificaciones_156_arnes.dart';
import '../helpers/qa_hojas_teclado_324_arnes.dart' show escucharAnuncios;

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

Rect _pantalla(WidgetTester tester) =>
    Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;

void main() {
  group('matriz de estados · sin desborde y con lo importante a la vista', () {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        for (final estado in EstadoCentro.values) {
          testWidgets('${estado.rotulo} · ${tam.nombre} · texto ${escala}x', (tester) async {
            await llevarAlEstado(tester, estado, tamano: tam, escala: escala);

            expect(tester.takeException(), isNull, reason: 'sin RenderFlex overflowed');
            final pantalla = _pantalla(tester);
            switch (estado) {
              case EstadoCentro.lista ||
                  EstadoCentro.avisosLargos ||
                  EstadoCentro.muchos ||
                  EstadoCentro.sinDestino:
                expect(centroLista, findsOneWidget);
                expect(centroMenu, findsOneWidget);
                expect(pantalla.contains(tester.getCenter(centroMenu)), isTrue);
              case EstadoCentro.menu || EstadoCentro.menuSinNuevas:
                for (final b in [menuMarcarTodas, menuBorrarTodas, menuCerrar]) {
                  expect(b, findsOneWidget);
                  await tester.ensureVisible(b);
                  await tester.pump();
                  expect(
                    pantalla.contains(tester.getRect(b).center),
                    isTrue,
                    reason: '$b alcanzable',
                  );
                }
              case EstadoCentro.confirmar ||
                  EstadoCentro.confirmarBorrando ||
                  EstadoCentro.confirmarConError:
                // La hoja se desplaza: los botones tienen que poder llegar a la vista.
                for (final b in [borrarConfirmar, borrarCancelar]) {
                  expect(b, findsOneWidget);
                  await tester.ensureVisible(b);
                  await tester.pump();
                  expect(
                    pantalla.contains(tester.getRect(b).center),
                    isTrue,
                    reason: '$b alcanzable',
                  );
                }
                if (estado == EstadoCentro.confirmarConError) {
                  expect(borrarError, findsOneWidget);
                  expect(find.text(TextosCentroNotificaciones.errorAlBorrar), findsOneWidget);
                }
              case EstadoCentro.vacio:
                expect(centroVacio, findsOneWidget);
                expect(centroMenu, findsNothing);
                expect(find.text(TextosCentroNotificaciones.vacioTitulo), findsOneWidget);
              case EstadoCentro.cargando:
                expect(centroCargando, findsOneWidget);
                expect(
                  find.byType(CircularProgressIndicator),
                  findsNothing,
                  reason: 'bloques, no spinner',
                );
              case EstadoCentro.error:
                expect(centroError, findsOneWidget);
                expect(centroReintentar, findsOneWidget);
                expect(pantalla.contains(tester.getRect(centroReintentar).center), isTrue);
            }
          });
        }
      }
    }
  });

  group('escenarios literales de la HU-NOT-005', () {
    testWidgets(
      'Ver historial: dado que recibí 5 notificaciones en la semana, cuando abro el centro, se '
      'listan de la más reciente a la más vieja y las no leídas tienen indicador',
      (tester) async {
        // Cinco en los últimos seis días, mezcladas a propósito: el orden es el del reloj.
        final cinco = [
          aviso('v2', hace: const Duration(days: 2)),
          aviso('v5', hace: const Duration(days: 5), leida: true),
          aviso('v0', hace: const Duration(minutes: 5)),
          aviso('v4', hace: const Duration(days: 4)),
          aviso('v1', hace: const Duration(days: 1), leida: true),
        ];
        await abrirCentro(tester, CentroArnes(avisos: cinco), tamano: const Size(390, 1600));

        final ids = ['v0', 'v1', 'v2', 'v4', 'v5'];
        final tops = [for (final id in ids) tester.getTopLeft(filaDe(id)).dy];
        expect(tops, orderedEquals([...tops]..sort()));
        for (final id in ['v0', 'v2', 'v4']) {
          expect(find.descendant(of: filaDe(id), matching: find.text('Nueva')), findsOneWidget);
        }
        for (final id in ['v1', 'v5']) {
          expect(find.descendant(of: filaDe(id), matching: find.text('Nueva')), findsNothing);
        }
      },
    );

    testWidgets(
      'Borrar todo: dado que tengo 30 notificaciones viejas, cuando presiono «Borrar todas», la '
      'tabla local queda vacía y la pantalla lo dice',
      (tester) async {
        final treinta = [
          for (var i = 0; i < 30; i++)
            aviso(
              'v-$i',
              hace: Duration(days: 8 + i),
              leida: i.isEven,
            ),
        ];
        final arnes = CentroArnes(avisos: treinta);
        await abrirCentro(tester, arnes, tamano: const Size(360, 640));

        await tester.tap(centroMenu);
        await tester.pumpAndSettle();
        await tester.tap(menuBorrarTodas);
        await tester.pumpAndSettle();
        expect(find.text('¿Borrar las 30 notificaciones?'), findsOneWidget);
        await tester.tap(borrarConfirmar);
        await tester.pumpAndSettle();

        expect(arnes.historial.filas, isEmpty);
        expect(centroVacio, findsOneWidget);
        expect(find.text('No tenés notificaciones'), findsOneWidget);
        expect(centroMenu, findsNothing, reason: 'sin avisos no hay nada que marcar ni borrar');
      },
    );
  });

  group('textos límite', () {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'textos largos, palabras sin cortes, emoji y caracteres especiales · ${tam.nombre} · '
          '${escala}x: se ven enteros (hasta el último renglón) y sin desborde',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llevarAlEstado(tester, EstadoCentro.avisosLargos, tamano: tam, escala: escala);

            expect(tester.takeException(), isNull);
            // Un texto largo no se recorta con puntos suspensivos: se parte en renglones.
            for (final t in tester.widgetList<Text>(
              find.descendant(of: centroLista, matching: find.byType(Text)),
            )) {
              expect(t.overflow, isNull, reason: '«${t.data}» no se recorta');
              expect(t.maxLines, isNull);
            }
            // El que lee con lector oye todo el aviso, con el texto completo.
            await tester.scrollUntilVisible(
              filaDe('l2'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            final fila = tester.getSemantics(filaDe('l2'));
            expect(fila.label, contains('A' * 80));
            expect(fila.label, contains('B' * 120));
            semantica.dispose();
          },
        );
      }
    }

    testWidgets('300 avisos: la lista es perezosa y se llega al último sin desborde', (
      tester,
    ) async {
      final arnes = await llevarAlEstado(
        tester,
        EstadoCentro.muchos,
        tamano: tamanos.first,
        escala: 2,
      );
      expect(arnes.historial.filas, hasLength(300));
      expect(find.byType(ListView), findsOneWidget);
      // No se construyen los 300 a la vez.
      expect(
        find.byWidgetPredicate((w) => w.key.toString().contains('centro_aviso_')).evaluate().length,
        lessThan(30),
      );

      await tester.scrollUntilVisible(
        filaDe('m-299'),
        2000,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 400,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(filaDe('m-299'), findsOneWidget);
      final fila = tester.getRect(filaDe('m-299'));
      expect(_pantalla(tester).contains(fila.bottomCenter - const Offset(0, 1)), isTrue);
    });
  });

  group('acciones superpuestas y fallas a mitad', () {
    testWidgets(
      'tocar un aviso mientras «Marcar todas» sigue en curso: ninguna acción se pierde ni se pisa',
      (tester) async {
        final arnes = CentroArnes(avisos: cincoDelCanvas());
        await abrirCentro(tester, arnes, tamano: const Size(360, 640));
        arnes.historial.puertaAlMarcarTodas = Completer<void>();

        await tester.tap(centroMenu);
        await tester.pumpAndSettle();
        await tester.tap(menuMarcarTodas);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Con «Marcar todas» colgada se toca un aviso: se abre y se marca como leído.
        await tester.tap(filaDe('a'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(arnes.abridor.abiertos, hasLength(1));
        expect(arnes.historial.marcadas, ['a']);

        arnes.historial.puertaAlMarcarTodas!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Nueva'), findsNothing);
        expect(arnes.historial.llamadasMarcarTodas, 1);
        expect(arnes.abridor.abiertos, hasLength(1), reason: 'no se abre dos veces');
      },
    );

    testWidgets(
      'una falla al marcar todas deja el menú usable: se vuelve a abrir y la segunda vez funciona',
      (tester) async {
        final arnes = CentroArnes(avisos: cincoDelCanvas());
        await abrirCentro(tester, arnes, tamano: const Size(360, 640));
        arnes.historial.fallaAlMarcarTodas = true;

        await tester.tap(centroMenu);
        await tester.pumpAndSettle();
        await tester.tap(menuMarcarTodas);
        await tester.pumpAndSettle();
        expect(find.text(TextosCentroNotificaciones.errorAlMarcar), findsOneWidget);
        expect(find.text('Nueva'), findsNWidgets(3), reason: 'nada cambió');

        arnes.historial.fallaAlMarcarTodas = false;
        await tester.tap(centroMenu);
        await tester.pumpAndSettle();
        await tester.tap(menuMarcarTodas);
        await tester.pumpAndSettle();
        expect(find.text('Nueva'), findsNothing);
      },
    );

    testWidgets(
      'la falla al borrar deja la hoja con qué hacer; cancelar la cierra y los avisos siguen',
      (tester) async {
        final arnes = await llevarAlEstado(
          tester,
          EstadoCentro.confirmarConError,
          tamano: tamanos.first,
          escala: 1,
        );
        expect(borrarError, findsOneWidget);
        expect(tester.widget<FilledButton>(borrarConfirmar).onPressed, isNotNull);

        await tester.tap(borrarCancelar);
        await tester.pumpAndSettle();
        expect(borrarTitulo, findsNothing);
        expect(arnes.historial.filas, hasLength(5));
        expect(find.byType(Scrollable), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'el borrado en curso no se puede cancelar ni cerrar con el atrás del sistema, y al terminar '
      'se cierra una sola vez',
      (tester) async {
        final arnes = await llevarAlEstado(
          tester,
          EstadoCentro.confirmarBorrando,
          tamano: tamanos.first,
          escala: 1,
        );
        expect(tester.widget<FilledButton>(borrarConfirmar).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(borrarCancelar).onPressed, isNull);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(borrarTitulo, findsOneWidget, reason: 'el atrás no cierra mientras borra');

        arnes.historial.puertaAlBorrar!.complete();
        await tester.pumpAndSettle();
        expect(borrarTitulo, findsNothing);
        expect(centroPagina, findsOneWidget, reason: 'sigue en el centro, no volvió a Hoy');
        expect(centroVacio, findsOneWidget);
      },
    );

    testWidgets('el atrás del sistema en el menú lo cierra y no saca el centro', (tester) async {
      await llevarAlEstado(tester, EstadoCentro.menu, tamano: tamanos.first, escala: 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(menuBorrarTodas, findsNothing);
      expect(centroPagina, findsOneWidget);
    });

    testWidgets('«Reintentar» tras un error: cuando la base responde se ve la lista', (
      tester,
    ) async {
      final arnes = await llevarAlEstado(
        tester,
        EstadoCentro.error,
        tamano: tamanos.first,
        escala: 1,
      );
      arnes.historial.errorAlObservar = null;
      await tester.tap(centroReintentar);
      await tester.pumpAndSettle();
      expect(centroError, findsNothing);
      expect(filaDe('a'), findsOneWidget);
      expect(centroMenu, findsOneWidget);
    });
  });

  group('lector de pantalla', () {
    testWidgets('el éxito de «Marcar todas» y de «Borrar todas» se anuncia una vez; la falla, no', (
      tester,
    ) async {
      final anuncios = escucharAnuncios(tester);
      final arnes = CentroArnes(avisos: cincoDelCanvas());
      await abrirCentro(tester, arnes, tamano: const Size(360, 640));

      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuMarcarTodas);
      await tester.pumpAndSettle();
      expect(anuncios, [TextosCentroNotificaciones.anuncioMarcadas]);

      arnes.historial.fallaAlBorrar = true;
      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
      await tester.tap(menuBorrarTodas);
      await tester.pumpAndSettle();
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();
      expect(anuncios, hasLength(1), reason: 'una falla no anuncia «se borraron»');

      arnes.historial.fallaAlBorrar = false;
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();
      expect(anuncios.last, TextosCentroNotificaciones.anuncioBorradas);
      expect(anuncios, hasLength(2));
    });

    testWidgets(
      'cada aviso, la campana del menú y los botones de las hojas tienen nombre y acción',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await llevarAlEstado(tester, EstadoCentro.lista, tamano: tamanos.first, escala: 2);
        for (final id in ['a', 'b', 'c', 'd', 'e']) {
          await tester.scrollUntilVisible(
            filaDe(id),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          final n = tester.getSemantics(filaDe(id));
          expect(n.label, isNotEmpty);
          expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: 'aviso $id');
        }
        expect(tester.getSemantics(centroMenu).tooltip, TextosCentroNotificaciones.menu);
        expect(tester.getSemantics(find.byKey(const Key('centro_atras'))).tooltip, 'Volver');
        semantica.dispose();
      },
    );
  });

  group('hallazgos', () {
    testWidgets(
      'el aviso de «Esa agenda ya no está» no tapa al aviso tocado cuando es el último de la lista',
      (tester) async {
        final arnes = CentroArnes(avisos: cincoDelCanvas());
        arnes.destinos.todosExisten = false;
        await abrirCentro(tester, arnes, tamano: const Size(360, 640), texto: 2);
        await tester.drag(centroLista, const Offset(0, -4000));
        await tester.pumpAndSettle();

        await tester.tap(filaDe('e'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final aviso = find.byType(SnackBar);
        expect(aviso, findsOneWidget);
        final cuerpo = tester.getRect(filaDe('e'));
        final tapado = tester.getRect(aviso).intersect(cuerpo);
        final dp = tapado.width > 0 && tapado.height > 0 ? tapado.height : 0;
        expect(dp, 0, reason: 'el aviso tapa $dp dp de la fila de ${cuerpo.height}');
      },
      skip: !_hallazgos,
    );

    testWidgets(
      'un aviso que llega con el menú abierto no entra en «Borrar todas» sin haberse contado',
      (tester) async {
        final arnes = CentroArnes(avisos: cincoDelCanvas());
        await abrirCentro(tester, arnes, tamano: const Size(360, 640));
        await tester.tap(centroMenu);
        await tester.pumpAndSettle();
        // Llega un recordatorio mientras el menú está abierto.
        arnes.historial.llegaUno(aviso('nuevo', hace: Duration.zero, titulo: 'Recién llegado'));
        await tester.pump();
        await tester.tap(menuBorrarTodas);
        await tester.pumpAndSettle();
        expect(find.text('¿Borrar las 5 notificaciones?'), findsOneWidget);
        await tester.tap(borrarConfirmar);
        await tester.pumpAndSettle();

        expect(
          arnes.historial.filas.map((f) => f.id),
          contains('nuevo'),
          reason: 'la confirmación dijo «las 5»; el aviso 6 no estaba en la cuenta',
        );
      },
      skip: !_hallazgos,
    );
  });
}
