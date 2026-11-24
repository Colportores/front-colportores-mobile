// QA de «Cargar de nuevo» del ticket rechazado de un cobro con tarjeta (#728, regla R7, vista 38B·02 →
// 29 C): criterios, estados alcanzables × 360×640 y 412×915 × texto 1,0 y 2,0 (guías de toque y de
// rótulo, sin overflow), el aviso de «no pudimos abrir el cobro» a la vista, casos límite y
// privacidad. Con `--dart-define=QA_CAPTURAS=true` guarda una captura de cada celda en
// `.dart_tool/qa_capturas/`.
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/presentation/textos_tickets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista38_388_arnes.dart';
import '../../helpers/qa_vista38_728_arnes.dart';
import '../../helpers/ticket_tarjeta_arnes.dart';

void main() {
  group('Criterios (R7 del 23/11, 38B·02)', () {
    testWidgets('el detalle rechazado dice el motivo literal y ofrece «Cargar de nuevo»', (
      tester,
    ) async {
      await abrirDetalle728(tester);

      expect(
        texto728('Tu coordinador lo rechazó: «No se lee el número». No se acreditó.'),
        findsOneWidget,
      );
      expect(find.descendant(of: boton728, matching: find.text('Cargar de nuevo')), findsOneWidget);
      expect(texto728('Tarjeta'), findsOneWidget, reason: 'la fila de la tarjeta del cobro');
      expect(texto728('004512'), findsOneWidget, reason: 'la aprobación');
    });

    testWidgets('sin motivo se dice solo lo que pasó y el botón sigue', (tester) async {
      await abrirDetalle728(tester, items: [rechazado728(motivo: null)]);

      expect(texto728(TextosTickets.rechazado(null)), findsOneWidget);
      expect(boton728, findsOneWidget);
    });

    for (final estado in [
      EstadoDelItem.validado,
      EstadoDelItem.porValidar,
      EstadoDelItem.enCola,
      EstadoDelItem.devuelto,
    ]) {
      testWidgets('un ticket de cobro con tarjeta ${estado.name} no ofrece «Cargar de nuevo»', (
        tester,
      ) async {
        await abrirDetalle728(tester, items: [rechazado728(estado: estado, motivo: null)]);

        expect(find.byKey(const Key('ticket_detalle')), findsOneWidget);
        expect(boton728, findsNothing);
      });
    }

    testWidgets('el depósito rechazado sigue abriendo el formulario de depósito, no la foto', (
      tester,
    ) async {
      await abrirDetalle728(
        tester,
        id: 'd2',
        items: [
          itemDePrueba(
            'd2',
            pesos: 2000,
            estado: EstadoDelItem.rechazado,
            motivo: 'La foto no se lee',
            tarjeta: null,
          ),
        ],
      );
      expect(boton728, findsOneWidget);
      await tester.tap(boton728);
      await tester.pumpAndSettle();

      expect(paginaTicket, findsNothing);
    });

    testWidgets('la foto del ticket sale con el cobro precargado: monto y aprobación a la vista', (
      tester,
    ) async {
      await abrirDetalle728(tester);
      await tocarCargarDeNuevo728(tester);
      await irALosDatos(tester);

      expect(paginaTicket, findsOneWidget);
      final monto = tester.widget<TextField>(campoMontoTicket).controller!.text;
      expect(monto.replaceAll(RegExp(r'[^0-9]'), ''), contains('1200'));
      expect(tester.widget<TextField>(campoAutorizacion).controller!.text, '004512');
    });
  });

  group('Estados × 360×640 y 412×915 × texto 1,0 y 2,0', () {
    for (final estado in Estado728.values) {
      for (final tamano in tamanos388) {
        for (final escala in escalas388) {
          final nombre = '${estado.name}_${sufijo388(tamano, escala)}';
          testWidgets('guías de toque y sin overflow: $nombre', (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA728(tester, estado, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull, reason: 'overflow en $nombre');

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await capturar388(tester, '728_$nombre');
            semantica.dispose();
          });
        }
      }
    }
  });

  group('El aviso de «no pudimos abrir el cobro» se ve (§8.3: qué pasa y qué hacer)', () {
    for (final largo in [false, true]) {
      for (final tamano in tamanos388) {
        for (final escala in escalas388) {
          final sufijo = '${largo ? 'motivo_largo' : 'motivo_corto'}_${sufijo388(tamano, escala)}';

          // El aviso va fijo arriba del botón (no dentro del scroll): con letra grande o con un motivo
          // largo sigue entero a la vista. QA #760: hallazgo 1.
          testWidgets('con el detalle arriba, el aviso queda a la vista: $sufijo', (tester) async {
            final e = await abrirDetalle728(
              tester,
              items: [rechazado728(motivo: largo ? motivoLargo728 : 'No se lee el número')],
              tamano: tamano,
              escala: escala,
            );
            e.repo.fallaAlLeerElCobro = StateError('sin base');
            await tocarCargarDeNuevo728(tester);

            await capturar388(tester, '728_aviso_$sufijo');
            // Armado, entero en la pantalla y sin pisar el botón.
            expect(
              avisoCobro728.evaluate().isNotEmpty && seVeFijoSobreElBoton728(tester, avisoCobro728),
              isTrue,
              reason: 'el aviso quedó cortado o fuera de vista',
            );
            expect(botonHabilitado728(tester), isTrue);
          });
        }
      }
    }

    testWidgets(
      'con el detalle desplazado hasta abajo, el aviso queda a la vista (2× en 360×640)',
      (tester) async {
        final e = await abrirDetalle728(tester, tamano: t360x640, escala: 2);
        final posicion = tester
            .state<ScrollableState>(
              find.descendant(of: lista728, matching: find.byType(Scrollable)).first,
            )
            .position;
        expect(posicion.maxScrollExtent, greaterThan(0), reason: 'a 2× hay que desplazarse');
        await tester.drag(lista728, Offset(0, -posicion.maxScrollExtent));
        await tester.pumpAndSettle();
        e.repo.fallaAlLeerElCobro = StateError('sin base');
        await tocarCargarDeNuevo728(tester);

        expect(
          avisoCobro728.evaluate().isNotEmpty && seVeFijoSobreElBoton728(tester, avisoCobro728),
          isTrue,
          reason: 'el error quedó fuera de vista',
        );
      },
    );
  });

  group('Casos límite', () {
    testWidgets('el aviso es una región viva (el lector lo anuncia) con su texto literal', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final e = await abrirDetalle728(tester);
      e.repo.fallaAlLeerElCobro = StateError('sin base');
      await tocarCargarDeNuevo728(tester);

      final nodo = tester.getSemantics(texto728(TextosTickets.cobroNoSePudoAbrir));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      expect(nodo.label, contains('No pudimos abrir el cobro de este ticket.'));
      expect(nodo.label, contains('Volvé a «Mis tickets» y probá de nuevo.'));
      semantica.dispose();
    });

    testWidgets('dos fallas seguidas dejan un solo aviso y el botón habilitado', (tester) async {
      final e = await abrirDetalle728(tester);
      e.repo.fallaAlLeerElCobro = StateError('sin base');
      await tocarCargarDeNuevo728(tester);
      e.repo.fallaAlLeerElCobro = StateError('sin base otra vez');
      await tocarCargarDeNuevo728(tester);

      expect(avisoCobro728, findsOneWidget);
      expect(botonHabilitado728(tester), isTrue);
      expect(e.repo.cobrosPedidos, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falla, vuelve a «Mis tickets» y reentra: el aviso no queda pegado', (
      tester,
    ) async {
      final e = await abrirDetalle728(tester);
      e.repo.fallaAlLeerElCobro = StateError('sin base');
      await tocarCargarDeNuevo728(tester);
      expect(avisoCobro728, findsOneWidget);

      await volverAtras(tester);
      await tester.tapAt(tester.getTopLeft(fila('c1')) + const Offset(30, 30));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ticket_detalle')), findsOneWidget);
      expect(avisoCobro728, findsNothing);
      expect(boton728, findsOneWidget);
    });

    testWidgets('con la lectura lenta, un segundo toque no pide el cobro dos veces', (
      tester,
    ) async {
      late RepoLento728 lento;
      await abrirDetalle728(tester, envolver: (base) => lento = RepoLento728(base));

      await tester.tap(boton728);
      await tester.pump();
      await tester.tap(boton728, warnIfMissed: false);
      await tester.pump();

      expect(lento.pedidos, 1);

      lento.espera.complete(cobroConTarjeta(id: 'cobro-c1'));
      await tester.pumpAndSettle();
      expect(paginaTicket, findsOneWidget);
      await tester.tap(atrasTicket);
      await tester.pumpAndSettle();
      expect(paginaTicket, findsNothing);
      expect(boton728, findsOneWidget, reason: 'el guardia se soltó: se puede volver a abrir');
    });

    testWidgets('si se sale del detalle con la lectura en vuelo, no se abre nada después', (
      tester,
    ) async {
      late RepoLento728 lento;
      await abrirDetalle728(tester, envolver: (base) => lento = RepoLento728(base));
      await tester.tap(boton728);
      await tester.pump();

      await volverAtras(tester);
      lento.espera.complete(cobroConTarjeta(id: 'cobro-c1'));
      await tester.pumpAndSettle();

      expect(paginaTicket, findsNothing, reason: 'nadie pidió la foto: el detalle ya no estaba');
      expect(find.byKey(const Key('tickets_lista')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si el historial se vacía con el detalle abierto, no se rompe el botón', (
      tester,
    ) async {
      final e = await abrirDetalle728(tester);
      e.repo.emitir(historialCon([]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ticket_detalle')), findsOneWidget);
    });

    testWidgets('el ticket nuevo cargado devuelve a la lista (el detalle no queda debajo)', (
      tester,
    ) async {
      await abrirDetalle728(tester);
      await tocarCargarDeNuevo728(tester);
      await enviarElTicket(tester);
      await tocarTicket(tester, find.byKey(const Key('ticket_listo')));

      expect(find.byKey(const Key('tickets_lista')), findsOneWidget);
      await volverAtras(tester);
      expect(
        find.byKey(const Key('abrir_historial')),
        findsOneWidget,
        reason: 'sin pantallas de más',
      );
    });
  });

  group('Privacidad', () {
    test('toString del item no imprime el motivo ni el número de autorización', () {
      final texto = rechazado728(motivo: 'Dato de otra persona', cobroId: 'cobro-1').toString();

      expect(texto, isNot(contains('Dato de otra persona')));
      expect(texto, isNot(contains('004512')));
    });
  });
}
