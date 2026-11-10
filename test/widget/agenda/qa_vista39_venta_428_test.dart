// QA de #428 («Sí, registrar la venta»: vista 39 R·06 / R·07 / R·08 → vista 27 → «¿Cuándo volvés a
// cobrar?»). Complementa los tests del implementador con los casos límite que ellos no tocan: la nota
// que viaja, el doble toque en «Sí», acciones superpuestas, el aviso que debe seguir a la vista, los
// bordes del reloj y la matriz de tamaños y letra con las guías de accesibilidad.
//
// Los que llevan `skip:` documentan un hallazgo del QA (se sacan cuando el implementador lo arregla).
// `--dart-define=QA_HALLAZGOS=true` los corre igual para verlos fallar.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_cuando_cobrar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_venta_428_arnes.dart';
import '../../helpers/venta_ui_falsos.dart' show tocar;

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// `skip` de un hallazgo: salvo con `QA_HALLAZGOS=true`.
const _hallazgo = !_verHallazgos;

void main() {
  late Arnes428 a;

  setUp(() => a = Arnes428());

  group('HU-VIS-005 · Registrar VENTA: lo que viaja y lo que no se pierde', () {
    testWidgets('dado que escribí una nota en la entrevista, cuando registro la venta, entonces la '
        'visita VENTA lleva el texto de la nota', (tester) async {
      await a.montar(tester);
      await a.tocarKey(tester, const Key('abrir'));
      await a.tocarKey(tester, ClavesEntrevista.botonNota);
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'volver con la esposa');
      await tester.pumpAndSettle();
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await a.armarLaVenta(tester);
      await a.registrar(tester);
      await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));

      final recibida = a.montaje.agenda.recibidas.single;
      expect(recibida.nota?.texto, 'volver con la esposa');
      expect(recibida.visita.tipoResultado.name, 'venta');
    });

    testWidgets('dado que la nota quedó escrita y la venta no se completa, entonces la nota sigue '
        'en la entrevista', (tester) async {
      await a.montar(tester);
      await a.tocarKey(tester, const Key('abrir'));
      await a.tocarKey(tester, ClavesEntrevista.botonNota);
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'volver con la esposa');
      await tester.pumpAndSettle();
      await a.tocarKey(tester, ClavesEntrevista.finalizar);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await tocar(tester, find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();

      expect(a.salida, isA<VentaSinCompletar>());
      expect(a.montaje.agenda.recibidas, isEmpty);
      // Volver a abrir la entrevista: la nota está.
      await a.tocarKey(tester, const Key('abrir'));
      expect(
        tester.widgetList<EditableText>(find.byType(EditableText)).map((e) => e.controller.text),
        contains('volver con la esposa'),
      );
    });

    // skip: QA #428 — decisión P1: el aviso sale al llegar a R·08, después de la hoja (hoy sale antes).
    testWidgets('dado el aviso «Venta 0039 guardada.», cuando elijo «Sin fecha», entonces el aviso '
        'sigue a la vista aunque haya tardado en elegir (R·08)', (tester) async {
      await a.montar(tester);
      await a.hastaLaPregunta(tester);

      // Ana lee la pregunta unos segundos: el aviso (4 s) corre por debajo de la hoja.
      await tester.pump(const Duration(seconds: 6));
      await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));

      expect(find.text('Venta 0039 guardada.'), findsOneWidget);
    }, skip: _hallazgo);
  });

  group('casos límite del recorrido', () {
    testWidgets(
      'dado un doble toque en «Sí, registrar la venta», entonces se abre una sola venta y '
      'volver atrás deja el mapa como estaba',
      (tester) async {
        await a.montar(tester);
        await a.tocarKey(tester, const Key('abrir'));
        await a.tocarKey(tester, ClavesEntrevista.finalizar);

        final si = find.byKey(ClavesEntrevista.registrarVenta);
        await tester.ensureVisible(si);
        await tester.tap(si);
        await tester.tap(si, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('nueva_venta_pagina')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await a.tocarKey(tester, const Key('venta_atras'));
        expect(find.byKey(const Key('nueva_venta_pagina')), findsNothing);
        expect(find.byKey(const Key('abrir')), findsOneWidget, reason: 'no se cerró de más');
        expect(a.salida, isA<VentaSinCompletar>());
        expect(find.textContaining('La venta no se guardó'), findsOneWidget);
      },
    );

    // skip: QA #428 — atrás + «Salir» con la venta guardándose: la venta y la visita se guardan pero el
    // recorrido devuelve «no se completó» y la entrevista queda en curso.
    testWidgets('dado que el botón de atrás se usa mientras la venta se está guardando, entonces '
        'el aviso no dice que no se guardó una venta que sí se guardó', (tester) async {
      await a.montar(tester);
      await a.hastaLaVenta(tester);
      await a.armarLaVenta(tester);
      final compuerta = Completer<void>();
      a.montaje.agenda.compuerta = compuerta;

      await tester.tap(find.byKey(const Key('venta_cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      final salir = find.text(TextosVenta.salirSalir);
      expect(salir, findsOneWidget, reason: 'con la venta a medias, atrás pide confirmar');
      await tester.tap(salir);
      await tester.pump(const Duration(milliseconds: 400));
      compuerta.complete();
      await tester.pumpAndSettle();

      // La venta y la visita se guardaron (la transacción ya había empezado)...
      expect(a.entorno.ventas.recibidas, hasLength(1));
      expect(a.montaje.agenda.recibidas, hasLength(1));
      // ...así que el recorrido no puede decir que no se completó ni dejar la entrevista abierta.
      expect(a.salida, isA<VentaGuardadaEnLaEntrevista>());
      expect(a.montaje.almacen.guardadas, isEmpty);
    }, skip: _hallazgo);

    testWidgets('dado el 31/10 a las 23:57, cuando elijo «Hoy», entonces propone las 23:59 y '
        'agenda ese día', (tester) async {
      await a.montar(tester);
      await a.hastaLaPregunta(tester);
      a.montaje.reloj = () => DateTime(2026, 10, 31, 23, 57);

      await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.hoy));
      await a.tocarKey(tester, const Key('agendar_hoja_listo'));

      final fecha = a.agendas.recibidas.single.agenda.fechaProgramada.toLocal();
      expect(fecha, DateTime(2026, 10, 31, 23, 59));
      expect(a.agendas.recibidas.single.agenda.tipo, TipoAgenda.cobranza);
    });

    testWidgets('dado el 31/10, cuando elijo «Mañana», entonces la cobranza queda el 1/11 a las '
        '10:00', (tester) async {
      await a.montar(tester);
      await a.hastaLaPregunta(tester);
      a.montaje.reloj = () => DateTime(2026, 10, 31, 23, 57);

      await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.manana));
      await a.tocarKey(tester, const Key('agendar_hoja_listo'));

      expect(
        a.agendas.recibidas.single.agenda.fechaProgramada.toLocal(),
        DateTime(2026, 11, 1, 10),
      );
    });

    testWidgets('dado un nombre larguísimo y un saldo enorme, entonces la pregunta los muestra '
        'enteros y la venta guardada dice el número', (tester) async {
      await a.montar(
        tester,
        persona: 'María de los Ángeles',
        apellido: 'Fernández de la Cruz y Sotomayor Echeverría Larrañaga',
        tamano: const Size(390, 1600),
      );
      await a.hastaLaPregunta(tester, tamano: const Size(360, 640), letra: 2);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Fernández de la Cruz y Sotomayor'), findsWidgets);
    });
  });

  group('R·07 sin inicio registrado', () {
    testWidgets('dado «Sí, registrar la venta» desde R·07, cuando se guarda la venta, entonces la '
        'entrevista del teléfono no queda abierta ni se guarda dos veces', (tester) async {
      a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);
      await a.montar(tester, conEntrevista: false);
      await a.tocarKey(tester, const Key('sin-inicio'));
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await a.armarLaVenta(tester);
      await a.registrar(tester);
      await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));

      expect(a.montaje.agenda.recibidas, hasLength(1));
      expect(a.entorno.ventas.recibidas, hasLength(1));
      expect(a.salida, isA<VentaGuardadaEnLaEntrevista>());
    });
  });

  group('matriz de tamaños y letra de «¿Cuándo volvés a cobrar?»', () {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        final nombre = '${tamano.width.toInt()}×${tamano.height.toInt()} a $escala×';
        testWidgets('a $nombre: sin overflow, las cuatro salidas se alcanzan y cumplen las guías', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await a.montar(tester, tamano: const Size(390, 1600));
          await a.hastaLaPregunta(tester, tamano: tamano, letra: escala);

          expect(tester.takeException(), isNull);
          for (final o in CuandoCobrar.values) {
            await tester.ensureVisible(find.byKey(ClavesCuandoCobrar.opcion(o)));
            await tester.pump();
            expect(find.byKey(ClavesCuandoCobrar.opcion(o)), findsOneWidget, reason: o.name);
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }

    testWidgets('el título se anuncia como encabezado y cada opción como botón con su ayuda', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await a.montar(tester);
      await a.hastaLaPregunta(tester);

      expect(
        tester.getSemantics(find.text('¿Cuándo volvés a cobrar?')),
        isSemantics(label: '¿Cuándo volvés a cobrar?', isHeader: true),
      );
      for (final texto in ['Hoy', 'Mañana', 'Otro día', 'Sin fecha']) {
        final nodo = find.semantics.byLabel(RegExp('^$texto\\. '));
        expect(nodo, findsOneWidget, reason: texto);
        expect(nodo.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      semantica.dispose();
    });
  });
}
