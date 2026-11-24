// «Registrar depósito» (vista 33 D, HU-CTA-004, #443): cada artboard del canvas (33D-01 a 33D-06), las
// piezas de la foto del ticket (38A) y los casos límite (doble toque, falla y reintento, volver atrás,
// texto al 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart'
    show TextosDescartar;
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/deposito_arnes.dart';
import '../../helpers/tickets_falsos.dart';

Finder _texto(String t) => find.text(t, findRichText: true);

void main() {
  group('33D-01 · el formulario', () {
    testWidgets('título, «En mano», monto, para qué, dónde, la foto, el número y la fecha', (
      tester,
    ) async {
      await montarDeposito(tester, ArnesDeDeposito());

      expect(_texto(TextosDeposito.eyebrow), findsOneWidget);
      expect(_texto(TextosDeposito.titulo), findsOneWidget);
      expect(_texto(r'En mano: $ 2.400'), findsOneWidget);
      expect(_texto(TextosDeposito.monto), findsOneWidget);
      for (final opcion in [
        TextosDeposito.casaEditora,
        TextosDeposito.alquiler,
        TextosDeposito.banco,
        TextosDeposito.oficina,
        TextosDeposito.retiro,
      ]) {
        expect(_texto(opcion), findsOneWidget, reason: opcion);
      }
      expect(_texto(TextosDeposito.sacarFotoDelTicket), findsOneWidget);
      expect(_texto(TextosDeposito.referencia), findsOneWidget);
      expect(find.textContaining('Hoy'), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);
      expect(_texto(TextosDeposito.faltanFotoYMonto), findsOneWidget);
    });

    testWidgets('sin monto o sin foto el botón dice qué falta; tocarlo lo marca y no registra', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);

      await escribirMonto(tester, '1800');
      expect(_texto(TextosDeposito.faltaLaFoto), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);

      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados, isEmpty);

      await escribirMonto(tester, '');
      await sacarLaFoto(tester);
      expect(_texto(TextosDeposito.faltaElMonto), findsWidgets);
      expect(botonRegistrar(tester).onPressed, isNull);
    });

    testWidgets('un monto que no es un número se marca', (tester) async {
      await montarDeposito(tester, ArnesDeDeposito());
      await escribirMonto(tester, '0');
      expect(_texto(TextosDeposito.montoInvalido), findsOneWidget);
    });
  });

  group('38A · la foto del ticket', () {
    testWidgets('cámara: la foto achicada queda en el recuadro y se puede cambiar', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);

      await sacarLaFoto(tester);

      expect(find.byKey(const Key('deposito_foto_miniatura')), findsOneWidget);
      expect(_texto(TextosDeposito.fotoCargada), findsOneWidget);
      expect(
        find.bySemanticsLabel(TextosDeposito.fotoCargadaEtiqueta),
        findsOneWidget,
        reason: 'el lector de pantalla dice que la foto está y que se puede cambiar',
      );

      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deposito_foto_galeria')));
      await tester.pumpAndSettle();
      expect((arnes.capturador as CapturadorGuionado).pedidos, ['camara', 'galeria']);
    });

    testWidgets('cerrar la hoja o cancelar la cámara no cambia nada', (tester) async {
      final arnes = ArnesDeDeposito(capturador: CapturadorGuionado([const CapturaCancelada()]));
      await montarDeposito(tester, arnes);

      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect((arnes.capturador as CapturadorGuionado).pedidos, isEmpty);

      await sacarLaFoto(tester);
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsNothing);
      expect(find.byKey(const Key('deposito_foto_error')), findsNothing);
    });

    testWidgets('sin permiso de cámara lo dice y deja elegir de la galería', (tester) async {
      final arnes = ArnesDeDeposito(
        capturador: CapturadorGuionado([
          const CapturaSinPermiso(),
          FotoCapturada(fotoDePrueba(4000)),
        ]),
      );
      await montarDeposito(tester, arnes);

      await sacarLaFoto(tester);
      expect(_texto(TextosDeposito.sinPermisoDeCamara), findsOneWidget);

      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deposito_foto_galeria')));
      await tester.pumpAndSettle();
      expect(_texto(TextosDeposito.sinPermisoDeCamara), findsNothing);
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsOneWidget);
    });

    testWidgets('una captura que falla lo dice', (tester) async {
      await montarDeposito(
        tester,
        ArnesDeDeposito(capturador: CapturadorGuionado([const CapturaFallida()])),
      );
      await sacarLaFoto(tester);
      expect(_texto(TextosDeposito.capturaFallida), findsOneWidget);
    });

    testWidgets('una foto que no se puede leer lo dice y no queda', (tester) async {
      await montarDeposito(tester, ArnesDeDeposito(legible: false));
      await sacarLaFoto(tester);
      expect(_texto(TextosDeposito.fotoIlegible), findsOneWidget);
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsNothing);
    });

    testWidgets('dos toques seguidos en la foto abren una sola hoja', (tester) async {
      await montarDeposito(tester, ArnesDeDeposito());

      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.tap(find.byKey(const Key('deposito_foto')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposito_foto_camara')), findsOneWidget);
    });

    testWidgets('en un teléfono sin cámara, el banco y la oficina no se pueden registrar', (
      tester,
    ) async {
      await montarDeposito(tester, ArnesDeDeposito(sinCamara: true));
      await escribirMonto(tester, '1800');

      expect(find.byKey(const Key('deposito_foto')), findsNothing);
      expect(_texto(TextosDeposito.sinCamara), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);

      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      expect(botonRegistrar(tester).onPressed, isNotNull);
    });
  });

  group('33D-02 · más de lo que tiene en mano', () {
    testWidgets('lo dice en el campo y apaga el botón', (tester) async {
      await montarDeposito(tester, ArnesDeDeposito());
      await sacarLaFoto(tester);
      await escribirMonto(tester, '3000');

      expect(_texto(r'Tenés $ 2.400 en mano.'), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);

      await escribirMonto(tester, '2400');
      expect(_texto(r'Tenés $ 2.400 en mano.'), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNotNull);
    });
  });

  group('33D-03 y 33D-04 · registrando y registrado', () {
    testWidgets('banco: guarda el ticket y el depósito, y muestra cómo quedó la plata', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      final resultados = await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('deposito_referencia')),
          matching: find.byType(TextField),
        ),
        '004512',
      );
      await tester.pump();

      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.montoCentavos, 180000);
      expect(deposito.destino, DestinoDeDeposito.banco);
      expect(deposito.concepto, ConceptoDeDeposito.casaEditora);
      expect(deposito.ticketId, 't-1');
      final ticket = arnes.tickets.guardados.single.ticket;
      expect(ticket.tipo, TipoDeTicket.deposito);
      expect(ticket.numeroAutorizacion, '004512');
      expect(ticket.montoCentavos, 180000);

      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
      expect(_texto(r'$ 2.400 → $ 600'), findsOneWidget);
      expect(_texto(r'$ 500 → $ 2.300'), findsOneWidget);
      expect(_texto(TextosDeposito.quedaPorValidarTicket), findsOneWidget);
      expect(find.byKey(const Key('deposito_se_envia_al_volver')), findsNothing);
      expect(
        find.bySemanticsLabel(r'En mano: de $ 2.400 a $ 600'),
        findsOneWidget,
        reason: 'el lector lee «de … a …», no la flecha',
      );

      await tester.tap(find.byKey(const Key('venta_cta')));
      await tester.pumpAndSettle();
      expect(resultados, [true]);
    });

    testWidgets('mientras registra el botón no responde y la pantalla no se cierra', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito()..depositos.espera = Completer<void>();
      final resultados = await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);

      await tocarRegistrar(tester, esperar: false);
      expect(_texto(TextosDeposito.registrando), findsOneWidget);
      await tester.tap(find.byKey(const Key('venta_cta')), warnIfMissed: false);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(arnes.depositos.guardados, hasLength(1), reason: 'un doble toque registra uno solo');
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      expect(resultados, isEmpty);

      arnes.depositos.espera!.complete();
      await tester.pumpAndSettle();
      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
    });

    testWidgets('retiro por el coordinador: sin foto y sin ticket', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();

      expect(find.byKey(const Key('deposito_foto')), findsNothing);
      expect(find.byKey(const Key('deposito_referencia')), findsNothing);
      expect(_texto(TextosDeposito.retiroSinFoto), findsOneWidget);

      await tocarRegistrar(tester);

      expect(arnes.tickets.guardados, isEmpty);
      final deposito = arnes.depositos.guardados.single;
      expect(deposito.destino, DestinoDeDeposito.retiroCoordinador);
      expect(deposito.ticketId, isNull);
      expect(_texto(TextosDeposito.quedaPorValidarRetiro), findsOneWidget);
    });

    testWidgets('una foto sacada y después «Retiro» no manda la foto', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1000');
      await sacarLaFoto(tester);
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();

      await tocarRegistrar(tester);

      expect(arnes.tickets.guardados, isEmpty);
      expect(arnes.depositos.guardados.single.ticketId, isNull);
    });

    testWidgets('oficina y un día anterior', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '600');
      await tester.tap(find.byKey(const Key('deposito_destino_1')));
      await tester.pump();
      await sacarLaFoto(tester);

      await verEnElFormulario(tester, const Key('cobro_fecha'));
      await tester.tap(find.byKey(const Key('cobro_fecha')));
      await tester.pumpAndSettle();
      expect(_texto(TextosDeposito.cuandoDepositaste), findsOneWidget);
      await tester.tap(find.text('9'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ayer'), findsOneWidget);

      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.destino, DestinoDeDeposito.oficina);
      expect(deposito.fecha, DateTime.utc(2026, 11, 9, 15));
      expect(arnes.tickets.guardados.single.ticket.fecha, DateTime.utc(2026, 11, 9, 15));
    });
  });

  group('alquiler', () {
    testWidgets('va a la campaña en curso', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '700');
      await tester.tap(find.byKey(const Key('deposito_concepto_1')));
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();

      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.concepto, ConceptoDeDeposito.alquiler);
      expect(deposito.campaniaId, 'camp-1');
    });

    testWidgets('sin campaña en curso lo dice y no deja registrarlo', (tester) async {
      await montarDeposito(tester, ArnesDeDeposito(campania: null));
      await escribirMonto(tester, '700');
      await tester.tap(find.byKey(const Key('deposito_concepto_1')));
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pumpAndSettle();

      expect(_texto(TextosDeposito.sinCampaniaParaElAlquiler), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);

      await tester.tap(find.byKey(const Key('deposito_concepto_0')));
      await tester.pump();
      expect(_texto(TextosDeposito.sinCampaniaParaElAlquiler), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNotNull);
    });
  });

  group('33D-05 · error', () {
    testWidgets('dice qué pasó, conserva lo cargado y «Reintentar» repite el mismo depósito', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito()
        ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado(causa: 'SqliteException');
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);

      await tocarRegistrar(tester);

      expect(find.byKey(const Key('deposito_error')), findsOneWidget);
      expect(_texto(const FailureDepositoNoGuardado().mensaje), findsOneWidget);
      expect(_texto(TextosDeposito.reintentar), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNotNull, reason: 'el botón vuelve a responder');
      expect(find.byKey(const Key('deposito_foto_miniatura')), findsOneWidget);

      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados.map((d) => d.id), ['d-1', 'd-1']);
      expect(arnes.tickets.guardados.map((t) => t.ticket.id), ['t-1', 't-1']);
      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
    });

    testWidgets('con otro monto después de la falla es otro depósito', (tester) async {
      final arnes = ArnesDeDeposito()
        ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      await escribirMonto(tester, '1700');
      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados.map((d) => d.id), ['d-1', 'd-2']);
    });

    testWidgets('el ticket ya usado se dice tal cual', (tester) async {
      final arnes = ArnesDeDeposito()
        ..depositos.fallarUnaVezCon = const FailureDepositoTicketYaUsado();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);
      expect(_texto(const FailureDepositoTicketYaUsado().mensaje), findsOneWidget);
    });
  });

  group('33D-06 · sin conexión', () {
    testWidgets('avisa que se envía después y registra igual', (tester) async {
      final arnes = ArnesDeDeposito(conexion: TipoConexion.sinConexion);
      await montarDeposito(tester, arnes);
      await tester.pumpAndSettle();

      expect(_texto(TextosDeposito.sinConexion), findsOneWidget);
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados, hasLength(1));
      expect(_texto(TextosDeposito.seEnviaAlVolver), findsOneWidget);
    });
  });

  group('volver atrás', () {
    testWidgets('sin nada escrito se cierra sin preguntar y se puede volver a entrar', (
      tester,
    ) async {
      final resultados = await montarDeposito(tester, ArnesDeDeposito());

      await tester.tap(find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
      expect(resultados, [false]);

      await abrirDeposito(tester);
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      expect(_texto(TextosDeposito.faltanFotoYMonto), findsOneWidget);
    });

    testWidgets('con algo escrito pregunta antes de descartar', (tester) async {
      final resultados = await montarDeposito(tester, ArnesDeDeposito());
      await escribirMonto(tester, '1800');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(TextosDescartar.titulo), findsOneWidget);

      await tester.tap(find.text(TextosDescartar.seguirEscribiendo));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      expect(find.text('1800'), findsOneWidget, reason: 'lo escrito sigue');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextosDescartar.descartar));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
      expect(resultados, [false]);
    });

    testWidgets('después de registrar, atrás cierra con «registrado»', (tester) async {
      final resultados = await montarDeposito(tester, ArnesDeDeposito());
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(resultados, [true]);
    });
  });

  group('accesibilidad', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('el formulario y el registrado entran a 320 × 640 con el texto a $escala', (
        tester,
      ) async {
        await montarDeposito(
          tester,
          ArnesDeDeposito(conexion: TipoConexion.sinConexion),
          tamano: const Size(320, 640),
          escala: escala,
        );
        await tester.pumpAndSettle();
        await escribirMonto(tester, '1800');
        await sacarLaFoto(tester);
        expect(tester.takeException(), isNull);

        await tocarRegistrar(tester);
        expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('48 dp, rótulos y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarDeposito(tester, ArnesDeDeposito());
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tocarRegistrar(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('un número de operación largo no rompe nada', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes, escala: 2);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await verEnElFormulario(tester, const Key('deposito_referencia'));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('deposito_referencia')),
          matching: find.byType(TextField),
        ),
        'X' * 60,
      );
      await tester.pump();
      await tocarRegistrar(tester);

      expect(tester.takeException(), isNull);
      expect(arnes.tickets.guardados.single.ticket.numeroAutorizacion, hasLength(40));
    });
  });
}
