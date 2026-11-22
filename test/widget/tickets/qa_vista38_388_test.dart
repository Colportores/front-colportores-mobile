// QA de «Mis tickets» y del detalle (vista 38B, HU-COB-009, #388): los escenarios literales de la HU,
// los avisos con salida, lo que se anuncia, la reentrada y los datos del formulario «Nº DE
// AUTORIZACIÓN» que llegan al ticket.
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/services/visor_de_fotos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista38_388_arnes.dart';

/// `--dart-define=QA_HALLAZGOS=true` corre los tests con `skip` para verlos fallar.
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

Finder _texto(String t) => find.text(t, findRichText: true);

Finder _enFila(String id, String texto) => find.descendant(of: fila(id), matching: _texto(texto));

Finder get _avisoQueSeAnuncia =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true);

Future<void> _abrirFila(WidgetTester tester, String id) async {
  await tester.ensureVisible(fila(id));
  await tester.pump();
  await tester.tapAt(tester.getTopLeft(fila(id)) + const Offset(30, 30));
  await tester.pumpAndSettle();
}

void main() {
  group('HU-COB-009 · escenarios de la HU, con su texto', () {
    testWidgets(
      'Dado que subí tres tickets (validado, pendiente y rechazado), cuando abro «Mis tickets», '
      'entonces veo los tres con su estado y en el rechazado veo el motivo',
      (tester) async {
        final repo = HistorialControlable(
          inicial: historialCon([
            itemDePrueba('pend'),
            itemDePrueba(
              'rech',
              fecha: DateTime.utc(2026, 10, 20, 15),
              estado: EstadoDelItem.rechazado,
              motivo: 'La foto no se lee',
            ),
            itemDePrueba(
              'val',
              fecha: DateTime.utc(2026, 10, 8, 15),
              estado: EstadoDelItem.validado,
              validadoEn: DateTime.utc(2026, 10, 9, 15),
            ),
          ]),
        );
        await montarHistorial(tester, repo);

        expect(_enFila('pend', 'Por validar'), findsOneWidget);
        expect(_enFila('rech', 'Rechazado'), findsOneWidget);
        expect(_enFila('val', 'Validado'), findsOneWidget);
        expect(
          _enFila('rech', 'Casa editora · La foto no se lee'),
          findsOneWidget,
          reason: 'el motivo se ve en la fila, sin abrirla',
        );
      },
    );

    testWidgets(
      'Dado que un ticket tiene más de 4 meses, cuando lo abro, entonces veo sus datos (fecha, '
      'monto, número de autorización, tarjeta) y un aviso de que la foto ya no está disponible',
      (tester) async {
        final repo = HistorialControlable(
          inicial: historialCon([
            itemDePrueba(
              'viejo',
              fecha: DateTime.utc(2026, 6, 20, 15),
              pesos: 4800,
              estado: EstadoDelItem.validado,
              validadoEn: DateTime.utc(2026, 6, 21, 15),
              fotoSubida: true,
              hayCopiaLocal: false,
            ),
          ]),
        );
        await montarHistorial(tester, repo, visor: VisorGuionado([const FotoVencida()]));
        await _abrirFila(tester, 'viejo');

        expect(_texto(r'$ 4.800'), findsOneWidget, reason: 'monto');
        expect(_texto('20/06'), findsOneWidget, reason: 'fecha');
        expect(_texto('004512'), findsOneWidget, reason: 'número de autorización');
        expect(_texto('Débito'), findsOneWidget, reason: 'tarjeta');
        expect(
          _texto(
            'La foto ya no está disponible: se guarda 4 meses. Los datos del ticket siguen acá.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('avisos con salida y que se anuncian', () {
    testWidgets('el error del historial se anuncia, trae «Reintentar» y no deja una lista vacía', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final repo = HistorialControlable()..fallaAlSuscribir = true;
      await montarHistorial(tester, repo);

      expect(_texto('No pudimos traer tus tickets.'), findsOneWidget);
      expect(
        find.descendant(of: _avisoQueSeAnuncia, matching: _texto('No pudimos traer tus tickets.')),
        findsOneWidget,
        reason: 'el aviso es una región viva',
      );
      expect(_texto('Reintentar'), findsOneWidget);
      expect(find.byKey(const Key('tickets_vacio')), findsNothing);
      expect(find.byKey(const Key('tickets_fila_d1')), findsNothing);
      semantica.dispose();
    });

    testWidgets('«Cargando» dice qué se carga (no es un spinner sin contexto)', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarHistorial(tester, HistorialControlable());

      expect(find.bySemanticsLabel('Cargando tus tickets'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('el detalle rechazado se anuncia y deja «Cargar de nuevo» a mano', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));
      await _abrirFila(tester, 'd2');

      expect(
        find.descendant(
          of: _avisoQueSeAnuncia,
          matching: _texto('Tu coordinador lo rechazó: «La foto no se lee». No se acreditó.'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('las filas de los filtros dicen cuál está elegido', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));

      expect(
        tester.getSemantics(find.byKey(const Key('tickets_filtro_todos'))),
        isSemantics(label: 'Todos', isSelected: true, isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('tickets_filtro_rechazados'))),
        isSemantics(label: 'Rechazados', isSelected: false, isButton: true, hasTapAction: true),
      );
      semantica.dispose();
    });
  });

  group('navegación y reentrada', () {
    for (final estado in [
      Estado388.cargando,
      Estado388.vacio,
      Estado388.error,
      Estado388.historial,
    ]) {
      testWidgets('con «${estado.name}», volver atrás deja la pantalla de antes', (tester) async {
        final armado = await llegarA388(tester, estado);
        await volverAtras(tester);

        expect(find.byKey(const Key('abrir_historial')), findsOneWidget);
        expect(find.byKey(const Key('tickets_pagina')), findsNothing);
        await soltar388(tester, armado);
      });
    }

    testWidgets('el filtro elegido sobrevive a una bajada nueva del servidor', (tester) async {
      final repo = HistorialControlable(inicial: historialCon(filasDelCanvas()));
      await montarHistorial(tester, repo);
      await tester.tap(find.byKey(const Key('tickets_filtro_rechazados')));
      await tester.pumpAndSettle();
      expect(fila('d1'), findsNothing);

      repo.emitir(
        historialCon([
          itemDePrueba('d9', estado: EstadoDelItem.rechazado, motivo: 'Borroso'),
          ...filasDelCanvas(),
        ]),
      );
      await tester.pumpAndSettle();

      expect(fila('d9'), findsOneWidget, reason: 'el rechazado nuevo aparece');
      expect(fila('d1'), findsNothing, reason: 'el filtro sigue en «Rechazados»');
    });

    testWidgets(
      'si el ticket abierto pasa a rechazado, el detalle lo dice y ofrece «Cargar de nuevo»',
      (tester) async {
        final repo = HistorialControlable(inicial: historialCon(filasDelCanvas()));
        await montarHistorial(tester, repo);
        await _abrirFila(tester, 'd1');
        expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsNothing);

        repo.emitir(
          historialCon([
            itemDePrueba('d1', estado: EstadoDelItem.rechazado, motivo: 'Cortado'),
            ...filasDelCanvas().skip(1),
          ]),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('ticket_aviso_rechazado')), findsOneWidget);
        expect(_texto('Tu coordinador lo rechazó: «Cortado». No se acreditó.'), findsOneWidget);
        expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsOneWidget);
      },
    );

    testWidgets('«Reintentar» de la foto dos veces seguidas no se traba ni pide de más', (
      tester,
    ) async {
      final visor = VisorGuionado([const FotoNoDisponible(sinRed: true)]);
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', fotoSubida: true, hayCopiaLocal: false)]),
      );
      await montarHistorial(tester, repo, visor: visor);
      await _abrirFila(tester, 'd1');

      await tester.tap(find.byKey(const Key('ticket_foto_reintentar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ticket_foto_reintentar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ticket_foto_reintentar')), findsOneWidget);
      expect(visor.pedidos.length, inInclusiveRange(2, 3));
      expect(tester.takeException(), isNull);
    });
  });

  group('ticket rechazado de un cobro con tarjeta', () {
    testWidgets(
      'se ve el motivo y no hay «Cargar de nuevo» (el ticket del cobro se carga desde el cobro)',
      (tester) async {
        final repo = HistorialControlable(
          inicial: historialCon([
            itemDePrueba(
              'c1',
              lugar: LugarDelTicket.cobroConTarjeta,
              concepto: null,
              estado: EstadoDelItem.rechazado,
              motivo: 'No se lee',
            ),
          ]),
        );
        await montarHistorial(tester, repo);
        await _abrirFila(tester, 'c1');

        expect(_texto('Tu coordinador lo rechazó: «No se lee». No se acreditó.'), findsOneWidget);
        expect(find.byKey(const Key('ticket_cargar_de_nuevo')), findsNothing);
      },
    );
  });

  group('«Nº DE AUTORIZACIÓN» del formulario llega al ticket', () {
    Future<ArnesDeDeposito> cargarConAutorizacion(WidgetTester tester, String texto) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await verEnElFormulario(tester, const Key('deposito_referencia'));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('deposito_referencia')),
          matching: find.byType(TextField),
        ),
        texto,
      );
      await tester.pump();
      await tocarRegistrar(tester);
      return arnes;
    }

    testWidgets('solo espacios: se registra sin número (no guarda espacios)', (tester) async {
      final arnes = await cargarConAutorizacion(tester, '     ');

      expect(arnes.tickets.guardados.single.ticket.numeroAutorizacion, isNull);
    });

    testWidgets('con espacios de más alrededor, se guarda recortado', (tester) async {
      final arnes = await cargarConAutorizacion(tester, '  004512  ');

      expect(arnes.tickets.guardados.single.ticket.numeroAutorizacion, '004512');
    });

    testWidgets(
      '30 emoji caben en el campo (40 puntos de código): el depósito se registra',
      (tester) async {
        final arnes = await cargarConAutorizacion(tester, '😀' * 30);

        expect(tester.takeException(), isNull);
        expect(
          arnes.tickets.guardados,
          hasLength(1),
          reason: 'lo que el campo acepta, el caso de uso no lo rechaza',
        );
      },
      // skip — QA #388: el campo cuenta puntos de código (30 emoji = 30) y el caso de uso cuenta
      // unidades UTF-16 (60 > 40): el depósito no se registra y la persona no sabe por qué.
      skip: !_verHallazgos,
    );
  });
}
