// «Mis tickets» (vista 38B, HU-COB-009, #388): cada artboard del canvas (38B·01 historial, 38B·04 sin
// tickets, 38B·05 cargando, 38B·06 sin conexión, 38B·07 error) y los casos límite (doble toque, volver
// atrás y reentrar, lista larga, textos largos, texto al 200 %, error y reintento).
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/deposito_arnes.dart';
import '../../helpers/historial_tickets_arnes.dart';

Finder _texto(String t) => find.text(t, findRichText: true);

Finder _enFila(String id, String texto) =>
    find.descendant(of: fila(id), matching: find.text(texto, findRichText: true));

void main() {
  group('38B·01 · el historial', () {
    testWidgets('la cabecera, los cuatro filtros y las cuatro filas del canvas', (tester) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));

      expect(_texto('MI CUENTA'), findsOneWidget);
      expect(_texto('Mis tickets'), findsOneWidget);
      for (final f in FiltroDeTickets.values) {
        expect(find.byKey(Key('tickets_filtro_${f.name}')), findsOneWidget, reason: f.name);
      }
      expect(_texto('+ Cargar ticket'), findsOneWidget);

      // Cada fila: «HOY · BANCO», el monto, el detalle y la etiqueta del estado.
      expect(_enFila('d1', 'HOY · BANCO'), findsOneWidget);
      expect(_enFila('d1', r'$ 4.800'), findsOneWidget);
      expect(_enFila('d1', 'Casa editora · débito · aut. 004512'), findsOneWidget);
      expect(_enFila('d1', 'Por validar'), findsOneWidget);

      expect(_enFila('d2', '20/10 · BANCO'), findsOneWidget);
      expect(_enFila('d2', r'$ 2.000'), findsOneWidget);
      expect(_enFila('d2', 'Casa editora · La foto no se lee'), findsOneWidget);
      expect(_enFila('d2', 'Rechazado'), findsOneWidget);

      expect(_enFila('d3', '15/10 · RETIRO'), findsOneWidget);
      expect(_enFila('d3', r'$ 6.000'), findsOneWidget);
      expect(_enFila('d3', 'Alquiler'), findsOneWidget);
      expect(_enFila('d3', 'Validado'), findsOneWidget);

      expect(_enFila('d4', '08/10 · OFICINA'), findsOneWidget);
      expect(_enFila('d4', r'$ 9.500'), findsOneWidget);
      expect(_enFila('d4', 'Validado'), findsOneWidget);
    });

    testWidgets('el lector de pantalla lee cada fila de una vez, con su estado', (tester) async {
      final manejador = tester.ensureSemantics();
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));

      expect(
        find.bySemanticsLabel(
          r'Por validar. Banco, hoy. $ 4.800. Casa editora · débito · aut. 004512.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          r'Rechazado. Banco, el 20/10. $ 2.000. Casa editora · La foto no se lee.',
        ),
        findsOneWidget,
      );
      manejador.dispose();
    });

    testWidgets('los filtros muestran solo lo suyo y «Todos» trae todo de vuelta', (tester) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));

      await tester.tap(find.byKey(const Key('tickets_filtro_porValidar')));
      await tester.pump();
      expect(
        [
          for (final id in ['d1', 'd2', 'd3', 'd4']) fila(id).evaluate().isNotEmpty,
        ],
        [true, false, false, false],
      );

      await tester.tap(find.byKey(const Key('tickets_filtro_rechazados')));
      await tester.pump();
      expect(
        [
          for (final id in ['d1', 'd2', 'd3', 'd4']) fila(id).evaluate().isNotEmpty,
        ],
        [false, true, false, false],
      );

      await tester.tap(find.byKey(const Key('tickets_filtro_alquiler')));
      await tester.pump();
      expect(
        [
          for (final id in ['d1', 'd2', 'd3', 'd4']) fila(id).evaluate().isNotEmpty,
        ],
        [false, false, true, false],
      );

      await tester.tap(find.byKey(const Key('tickets_filtro_todos')));
      await tester.pump();
      expect(
        [
          for (final id in ['d1', 'd2', 'd3', 'd4']) fila(id).evaluate().isNotEmpty,
        ],
        [true, true, true, true],
      );
    });

    testWidgets('un filtro sin resultados lo dice y deja los filtros a la vista', (tester) async {
      final soloValidados = [filasDelCanvas()[2], filasDelCanvas()[3]];
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(soloValidados)));

      await tester.tap(find.byKey(const Key('tickets_filtro_porValidar')));
      await tester.pump();

      expect(find.byKey(const Key('tickets_vacio_del_filtro')), findsOneWidget);
      expect(_texto('No tenés tickets por validar.'), findsOneWidget);
      expect(find.byKey(const Key('tickets_filtro_todos')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tickets_filtro_todos')));
      await tester.pump();
      expect(find.byKey(const Key('tickets_vacio_del_filtro')), findsNothing);
      expect(fila('d3'), findsOneWidget);
    });

    testWidgets('tocar una fila abre su detalle y volver atrás deja la lista como estaba', (
      tester,
    ) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));
      await tester.tap(find.byKey(const Key('tickets_filtro_rechazados')));
      await tester.pump();

      await tester.tap(fila('d2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ticket_detalle')), findsOneWidget);

      await volverAtras(tester);
      expect(find.byKey(const Key('ticket_detalle')), findsNothing);
      expect(fila('d2'), findsOneWidget);
      expect(fila('d1'), findsNothing, reason: 'el filtro sigue donde estaba');
    });

    testWidgets('un doble toque en la fila abre un solo detalle', (tester) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));

      await tester.tap(fila('d1'));
      await tester.tap(fila('d1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ticket_detalle')), findsOneWidget);

      await volverAtras(tester);
      expect(find.byKey(const Key('ticket_detalle')), findsNothing, reason: 'no había dos');
      expect(find.byKey(const Key('tickets_pagina')), findsOneWidget);
    });

    testWidgets('salir y volver a entrar arranca de nuevo en «Todos»', (tester) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));
      await tester.tap(find.byKey(const Key('tickets_filtro_rechazados')));
      await tester.pump();
      expect(fila('d1'), findsNothing);

      await volverAtras(tester);
      await abrirHistorial(tester);

      expect(fila('d1'), findsOneWidget);
      expect(fila('d2'), findsOneWidget);
    });

    testWidgets('un ticket nuevo que llega mientras se mira entra solo, arriba', (tester) async {
      final repo = HistorialControlable(inicial: historialCon([filasDelCanvas()[1]]));
      await montarHistorial(tester, repo);
      expect(fila('d1'), findsNothing);

      repo.emitir(historialCon([filasDelCanvas()[0], filasDelCanvas()[1]]));
      await tester.pump();

      expect(fila('d1'), findsOneWidget);
      expect(
        tester.getTopLeft(fila('d1')).dy < tester.getTopLeft(fila('d2')).dy,
        isTrue,
        reason: 'el de hoy va arriba',
      );
    });

    testWidgets('un ticket que cambia de estado se ve cambiar sin salir de la lista', (
      tester,
    ) async {
      final repo = HistorialControlable(inicial: historialCon([filasDelCanvas()[0]]));
      await montarHistorial(tester, repo);
      expect(_enFila('d1', 'Por validar'), findsOneWidget);

      repo.emitir(
        historialCon([
          itemDePrueba(
            'd1',
            estado: EstadoDelItem.validado,
            validadoEn: DateTime.utc(2026, 11, 11, 15),
          ),
        ]),
      );
      await tester.pump();

      expect(_enFila('d1', 'Validado'), findsOneWidget);
      expect(_enFila('d1', 'Por validar'), findsNothing);
    });

    testWidgets('una lista larga se arma de a poco y se llega hasta la última fila', (
      tester,
    ) async {
      final muchas = [
        for (var i = 0; i < 60; i++)
          itemDePrueba(
            'm${i.toString().padLeft(2, '0')}',
            fecha: DateTime.utc(2026, 11, 10, 15).subtract(Duration(days: i)),
            pesos: 100 + i,
          ),
      ];
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(muchas)));

      expect(
        fila('m59'),
        findsNothing,
        reason: 'la lista es perezosa: lo de abajo todavía no existe',
      );
      await tester.scrollUntilVisible(
        fila('m59'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('tickets_lista')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(fila('m59'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«+ Cargar ticket» sigue a la vista con la lista larga', (tester) async {
      final muchas = [for (var i = 0; i < 40; i++) itemDePrueba('m$i', pesos: 100 + i)];
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(muchas)));

      expect(find.byKey(const Key('tickets_cargar')), findsOneWidget);
      expect(tester.getBottomLeft(find.byKey(const Key('tickets_cargar'))).dy, lessThan(844));
    });
  });

  group('38B·04 · sin tickets', () {
    testWidgets('dice que todavía no hay y qué hacer, sin filtros, con el botón para cargar', (
      tester,
    ) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(const [])));

      expect(find.byKey(const Key('tickets_vacio')), findsOneWidget);
      expect(_texto('Todavía no cargaste tickets'), findsOneWidget);
      expect(
        _texto('Cuando deposites o tu coordinador retire el dinero, cargá el ticket acá.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tickets_filtro_todos')), findsNothing);
      expect(_texto('+ Cargar ticket'), findsOneWidget);
    });
  });

  group('38B·05 · cargando', () {
    testWidgets('un bloque gris por fila hasta que llega la lista, y después desaparece', (
      tester,
    ) async {
      final repo = HistorialControlable();
      await montarHistorial(tester, repo);

      expect(find.byKey(const Key('tickets_cargando')), findsOneWidget);
      expect(find.byKey(const Key('tickets_vacio')), findsNothing, reason: 'cargando no es vacío');

      repo.emitir(historialCon(filasDelCanvas()));
      await tester.pump();

      expect(find.byKey(const Key('tickets_cargando')), findsNothing);
      expect(fila('d1'), findsOneWidget);
    });
  });

  group('38B·06 · sin conexión', () {
    testWidgets('dice de cuándo son los estados y lo que no llegó queda «En cola»', (tester) async {
      final enCola = itemDePrueba('d0', estado: EstadoDelItem.enCola);
      await montarHistorial(
        tester,
        HistorialControlable(inicial: historialCon([enCola, ...filasDelCanvas().skip(2)])),
        arnes: ArnesDeDeposito(conexion: TipoConexion.sinConexion),
      );

      expect(_texto('Sin conexión. Los estados son de ayer a las 21:00.'), findsOneWidget);
      expect(_enFila('d0', 'En cola'), findsOneWidget);
      expect(_enFila('d0', 'Se envía cuando vuelva la red'), findsOneWidget);
      expect(_enFila('d3', 'Validado'), findsOneWidget);
    });

    testWidgets('si el teléfono todavía no bajó nada, no inventa una hora', (tester) async {
      await montarHistorial(
        tester,
        HistorialControlable(inicial: HistorialDeTickets(items: [itemDePrueba('d1')])),
        arnes: ArnesDeDeposito(conexion: TipoConexion.sinConexion),
      );

      expect(_texto('Sin conexión. Los estados son los que guardó el teléfono.'), findsOneWidget);
    });

    testWidgets('con conexión no hay aviso', (tester) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));

      expect(find.textContaining('Sin conexión'), findsNothing);
    });
  });

  group('38B·07 · error', () {
    testWidgets('dice qué pasó, no muestra una lista vacía y «Reintentar» vuelve a leer', (
      tester,
    ) async {
      final repo = HistorialControlable(inicial: historialCon(filasDelCanvas()))
        ..fallaAlSuscribir = true;
      await montarHistorial(tester, repo);

      expect(_texto('No pudimos traer tus tickets.'), findsOneWidget);
      expect(find.byKey(const Key('tickets_vacio')), findsNothing);
      expect(find.byKey(const Key('tickets_cargando')), findsNothing);
      expect(_texto('+ Cargar ticket'), findsOneWidget, reason: 'cargar un ticket sigue a mano');

      repo.fallaAlSuscribir = false;
      await tester.tap(find.byKey(const Key('cuenta_reintentar')));
      await tester.pump();
      await tester.pump();

      expect(repo.suscripciones, 2);
      expect(_texto('No pudimos traer tus tickets.'), findsNothing);
      expect(fila('d1'), findsOneWidget);
    });

    testWidgets('si el reintento también falla, el error sigue y se puede reintentar de nuevo', (
      tester,
    ) async {
      final repo = HistorialControlable()..fallaAlSuscribir = true;
      await montarHistorial(tester, repo);

      await tester.tap(find.byKey(const Key('cuenta_reintentar')));
      await tester.pump();
      await tester.pump();

      expect(_texto('No pudimos traer tus tickets.'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_reintentar')), findsOneWidget);
      expect(repo.suscripciones, 2);
    });
  });

  group('«+ Cargar ticket»', () {
    testWidgets('abre el formulario de depósito, y al registrar vuelve a la lista', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarHistorial(
        tester,
        HistorialControlable(inicial: historialCon(filasDelCanvas())),
        arnes: arnes,
      );

      await tester.tap(find.byKey(const Key('tickets_cargar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);

      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados, hasLength(1));
      expect(
        find.byKey(const Key('deposito_ver_mis_tickets')),
        findsNothing,
        reason: 'ya está debajo',
      );
      await tester.tap(find.byKey(const Key('deposito_listo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tickets_pagina')), findsOneWidget);
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
    });

    testWidgets('un doble toque abre un solo formulario', (tester) async {
      await montarHistorial(tester, HistorialControlable(inicial: historialCon(filasDelCanvas())));

      await tester.tap(find.byKey(const Key('tickets_cargar')));
      await tester.tap(find.byKey(const Key('tickets_cargar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
      await tester.tap(find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing, reason: 'no había dos');
    });
  });

  group('datos límite', () {
    testWidgets('un motivo muy largo y el texto al 200 % en una pantalla chica no desbordan', (
      tester,
    ) async {
      final largo = List.filled(
        12,
        'La foto está movida y no se alcanza a leer el número',
      ).join(' ');
      final items = [
        itemDePrueba('d2', estado: EstadoDelItem.rechazado, motivo: largo, pesos: 21000000),
        ...filasDelCanvas().skip(2),
      ];
      await montarHistorial(
        tester,
        HistorialControlable(inicial: historialCon(items)),
        tamano: const Size(320, 568),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('tickets_cargar')), findsOneWidget);
      await tester.scrollUntilVisible(
        fila('d4'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('tickets_lista')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('el vacío cabe en 320×568 al 200 %', (tester) async {
      final repo = HistorialControlable(inicial: historialCon(const []));
      await montarHistorial(tester, repo, tamano: const Size(320, 568), escala: 2);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('tickets_vacio')), findsOneWidget);
    });

    testWidgets('los filtros pasan a otra línea con el texto grande y se tocan igual', (
      tester,
    ) async {
      await montarHistorial(
        tester,
        HistorialControlable(inicial: historialCon(filasDelCanvas())),
        tamano: const Size(320, 568),
        escala: 2,
      );

      await tester.tap(find.byKey(const Key('tickets_filtro_alquiler')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fila('d3'), findsOneWidget);
      expect(fila('d1'), findsNothing);
    });

    testWidgets('el vacío de «Rechazados» y de «Alquiler» dice lo suyo', (tester) async {
      await montarHistorial(
        tester,
        HistorialControlable(inicial: historialCon([filasDelCanvas()[0]])),
      );

      await tester.tap(find.byKey(const Key('tickets_filtro_rechazados')));
      await tester.pump();
      expect(_texto('No tenés tickets rechazados.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tickets_filtro_alquiler')));
      await tester.pump();
      expect(_texto('No tenés tickets de alquiler.'), findsOneWidget);
    });

    testWidgets('el ticket de un cobro con tarjeta se muestra sin concepto', (tester) async {
      final cobro = itemDePrueba(
        'c1',
        lugar: LugarDelTicket.cobroConTarjeta,
        concepto: null,
        ticketId: 't-c1',
        autorizacion: '9981',
        tarjeta: null,
      );
      await montarHistorial(tester, HistorialControlable(inicial: historialCon([cobro])));

      expect(_enFila('c1', 'HOY · COBRO CON TARJETA'), findsOneWidget);
      expect(_enFila('c1', 'aut. 9981'), findsOneWidget);
    });

    testWidgets('un depósito de alquiler en cola dice solo que se envía cuando vuelva la red', (
      tester,
    ) async {
      final item = itemDePrueba(
        'a1',
        concepto: ConceptoDeDeposito.alquiler,
        estado: EstadoDelItem.enCola,
      );
      await montarHistorial(tester, HistorialControlable(inicial: historialCon([item])));

      expect(_enFila('a1', 'Se envía cuando vuelva la red'), findsOneWidget);
      expect(_enFila('a1', 'En cola'), findsOneWidget);
    });
  });
}
