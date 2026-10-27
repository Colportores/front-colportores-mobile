// QA de la pestaña «Agenda» (vista 23B, HU-VIS-002, #148): matriz de estados × teléfonos × escala de
// texto con las fuentes reales, la HU en sus palabras, los casos límite que los tests del PR no
// miran (barrido de escalas, alcanzar la última fila, lo tipeado tras un error) y las capturas.
//
// Capturas: `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, nunca al repo).
// Los hallazgos con `skip` se ven fallar con `--dart-define=QA_HALLAZGOS=true`.
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/qa_agenda_148_arnes.dart';

void main() {
  group('HU-VIS-002 · criterios de aceptación, en sus palabras', () {
    probar('Vista del día: 3 agendas hoy y 5 mañana → «Hoy (3)» y «Mañana (5)» con detalle', (
      tester,
    ) async {
      final hoy = DateTime(2026, 10, 28);
      final manana = DateTime(2026, 10, 29);
      await montar(
        tester,
        ConsultaAgendaFalsa([
          for (var i = 0; i < 3; i++)
            entrevista('h$i', hoy.add(Duration(hours: 11 + i)), nombre: 'Hoy$i'),
          for (var i = 0; i < 5; i++)
            cobranza('m$i', manana.add(Duration(hours: 9 + i)), nombre: 'Mañ$i'),
        ]),
        tamano: telefonoGrande,
      );

      expect(find.text('HOY · MIÉRCOLES 28 (3)'), findsOneWidget);
      // Cronológico: las tres de hoy, de arriba abajo, en orden de hora.
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Hoy0 Martínez'), lessThan(y('Hoy1 Martínez')));
      expect(y('Hoy1 Martínez'), lessThan(y('Hoy2 Martínez')));
      for (var i = 0; i < 3; i++) {
        expect(find.text('Hoy$i Martínez'), findsOneWidget);
      }
      for (var i = 0; i < 5; i++) {
        await tester.scrollUntilVisible(
          find.text('Mañ$i Martínez'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Mañ$i Martínez'), findsOneWidget);
      }
      expect(find.text('MAÑANA · JUEVES 29 (5)'), findsOneWidget);
    });

    probar('Filtro entrevista: con tipo=ENTREVISTA solo se ven entrevistas, y los conteos siguen', (
      tester,
    ) async {
      final hoy = DateTime(2026, 10, 28);
      await montar(
        tester,
        ConsultaAgendaFalsa([
          entrevista('e1', hoy.add(const Duration(hours: 11)), nombre: 'Ana'),
          cobranza('c1', hoy.add(const Duration(hours: 12)), nombre: 'Luis'),
          entrevista('e2', hoy.add(const Duration(hours: 13)), nombre: 'Marta'),
          cobranza('c2', DateTime(2026, 10, 29, 9), nombre: 'Pedro'),
        ]),
        tamano: telefonoGrande,
      );
      expect(find.text('HOY · MIÉRCOLES 28 (3)'), findsOneWidget);

      await tester.tap(find.text('Entrevistas'));
      await asentar(tester);

      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(find.text('Marta Martínez'), findsOneWidget);
      expect(find.text('Luis Martínez'), findsNothing);
      expect(find.text('Pedro Martínez'), findsNothing);
      expect(find.text('Cobranza'), findsNothing);
      expect(find.text('HOY · MIÉRCOLES 28 (2)'), findsOneWidget);
      // Mañana solo tenía una cobranza: el día desaparece, no queda un «(0)».
      expect(find.textContaining('MAÑANA'), findsNothing);
    });
  });

  group('Matriz de estados × teléfonos × escala (fuentes reales)', () {
    for (final e in Estado148.values) {
      for (final tamano in tamanos) {
        for (final escala in escalas) {
          final celda =
              '${e.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ${escala}x';
          testWidgets('sin overflow, sin texto fuera, 48 dp y con nombre: $celda', (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA(tester, e, escala: escala, tamano: tamano);

            expect(tester.takeException(), isNull, reason: celda);
            expectSinTextoFueraDeLosCostados(tester, tamano);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await capturar(tester, '${e.id}_${tamano.width.toInt()}_${escala}x');
            semantica.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
          });
        }
      }
    }
  });

  group('Barrido de la escala del texto (1,0× a 2,0×)', () {
    for (final e in [Estado148.e01, Estado148.e02, Estado148.atrasadas, Estado148.larga]) {
      testWidgets('${e.rotulo} a 360×640: sin overflow en ninguna escala', (tester) async {
        for (var paso = 0; paso <= 10; paso++) {
          final escala = 1 + paso / 10;
          await llegarA(tester, e, escala: escala);
          expect(tester.takeException(), isNull, reason: '${e.rotulo} a $escala×');
          expectSinTextoFueraDeLosCostados(tester, telefonoChico);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }

    /// Cuántas líneas ocupa el texto [buscado] de la primera coincidencia.
    int lineasDe(WidgetTester tester, Finder buscado) {
      final parrafo = tester.renderObject<RenderParagraph>(buscado.first);
      final cajas = parrafo.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: parrafo.text.toPlainText().length),
      );
      return {for (final c in cajas) c.top.round()}.length;
    }

    testWidgets('la fecha de una atrasada («25/10») no se parte, de 1,0× a 2,0×', (tester) async {
      for (var paso = 0; paso <= 10; paso++) {
        final escala = 1 + paso / 10;
        await llegarA(tester, Estado148.atrasadas, escala: escala);
        final texto = find.textContaining('25/10');
        expect(texto, findsOneWidget, reason: '$escala×');
        // Apilada (desde 1,3×) va «25/10 · 11:00» en una línea; sin apilar, «25/10» y «11:00».
        expect(lineasDe(tester, texto), escala >= 1.3 ? 1 : 2, reason: 'se parte a $escala×');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    // QA #148 (arreglado): con el texto al 130 % (el «Grande» de Android) la hora y la fecha de las
    // atrasadas se partían letra por letra dentro de los 44 dp; ahora la fila apila desde 1,3×.
    testWidgets('la fecha de una atrasada («25/10») no se parte a 1,3× (el «Grande» de Android)', (
      tester,
    ) async {
      await llegarA(tester, Estado148.atrasadas, escala: 1.3);
      final texto = find.textContaining('25/10');

      expect(lineasDe(tester, texto), lessThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('la hora de cada fila («16:00») queda en una línea, de 1,0× a 2,0×', (
      tester,
    ) async {
      for (var paso = 0; paso <= 10; paso++) {
        final escala = 1 + paso / 10;
        await llegarA(tester, Estado148.e01, escala: escala);
        expect(lineasDe(tester, find.textContaining('16:00')), 1, reason: '16:00 a $escala×');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    // QA #148 (arreglado): con el texto al 130 % (el «Grande» de Android) la hora de TODAS las filas
    // («16:00») se partía en dos líneas dentro de los 44 dp de su columna.
    testWidgets(
      'la hora de cada fila («16:00») queda en una línea a 1,3× (el «Grande» de Android)',
      (tester) async {
        await llegarA(tester, Estado148.e01, escala: 1.3);
        await capturar(tester, 'hallazgo_hora_1.3x');

        expect(lineasDe(tester, find.textContaining('16:00')), 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('Alcanzar todo con el texto grande', () {
    probar('a 360×640 y 2,0× la última fila de la semana se alcanza y se toca', (tester) async {
      final d = Destinos();
      await montar(tester, ConsultaAgendaFalsa(itemsDe(Estado148.e01)), escala: 2, destinos: d);

      await tester.scrollUntilVisible(
        find.text('Laura Martínez'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Laura Martínez'));
      await asentar(tester);

      expect(d.detalle, ['e3']);
    });

    probar('con 30 agendas en un día, la última se alcanza', (tester) async {
      await montar(tester, ConsultaAgendaFalsa(itemsDe(Estado148.muchas)), escala: 2);
      expect(find.text('HOY · MIÉRCOLES 28 (30)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Persona 29 Martínez'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Persona 29 Martínez'), findsOneWidget);
    });
  });

  group('Después de un error, lo elegido no se pierde', () {
    probar('el filtro «Cobranzas» sigue puesto tras un error de lectura y «Reintentar»', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(itemsDe(Estado148.e01));
      await montar(tester, repo);
      await tester.tap(find.text('Cobranzas'));
      await asentar(tester);
      expect(find.text('Jorge Martínez'), findsNothing);

      repo.emitirError(StateError('disco'));
      await asentar(tester);
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      repo.error = null;
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(find.text('No pudimos leer tu agenda.'), findsNothing);
      expect(find.text('María Martínez'), findsOneWidget);
      expect(find.text('Jorge Martínez'), findsNothing, reason: 'el filtro Cobranzas se perdió');
    });

    probar('el error no deja la pestaña sin salida: «Reintentar» queda a 48 dp y con nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llegarA(tester, Estado148.e09, tamano: telefonoChico, escala: 2);

      expect(
        tester.getSize(find.widgetWithText(InkWell, 'Reintentar')).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.bySemanticsLabel('No pudimos leer tu agenda.'), findsWidgets);
      semantica.dispose();
    });
  });

  group('Bordes de la ventana (hoy + 7 días)', () {
    probar('00:00 de hoy y 23:59 del día 7 entran; 00:00 del día 8 y 23:59 de ayer no son de la '
        'ventana', (tester) async {
      await montar(
        tester,
        ConsultaAgendaFalsa([
          entrevista('a', DateTime(2026, 10, 28, 0, 0), nombre: 'Inicio'),
          entrevista('b', DateTime(2026, 11, 4, 23, 59), nombre: 'Fin'),
          entrevista('c', DateTime(2026, 11, 5, 0, 0), nombre: 'Dia8'),
          itemAgenda(
            'd',
            DateTime(2026, 10, 27, 23, 59),
            nombre: 'Ayer',
            estado: EstadoAgenda.cumplida,
          ),
        ]),
        tamano: telefonoGrande,
      );

      expect(find.text('Inicio Martínez'), findsOneWidget);
      expect(find.text('Fin Martínez'), findsOneWidget);
      expect(find.text('Dia8 Martínez'), findsNothing);
      expect(find.text('Ayer Martínez'), findsNothing);
    });
  });

  group('Hallazgos de QA (el de «+ Agendar» sigue con skip: QA_HALLAZGOS=true)', () {
    // QA #148 (arreglado): los cuatro chips de filtro quedaban uno debajo del otro, cada uno a todo
    // el ancho, en lugar de una sola fila como en 23B·01 a 23B·09 (el `Container(alignment)` se
    // estiraba al ancho del `Wrap`).
    for (final tamano in tamanos) {
      probar(
        'los chips de filtro van en una sola fila (23B·01) a ${tamano.width.toInt()}×${tamano.height.toInt()}',
        (tester) async {
          await montar(tester, ConsultaAgendaFalsa(itemsDe(Estado148.e01)), tamano: tamano);

          final todas = tester.getRect(find.widgetWithText(InkWell, 'Todas'));
          final entrevistas = tester.getRect(find.widgetWithText(InkWell, 'Entrevistas'));
          final cobranzas = tester.getRect(find.widgetWithText(InkWell, 'Cobranzas'));
          expect(entrevistas.top, todas.top, reason: 'Entrevistas debajo de Todas');
          expect(cobranzas.top, todas.top, reason: 'Cobranzas debajo de Todas');
          expect(todas.width, lessThan(tamano.width / 2), reason: 'chip a todo el ancho');
        },
      );
    }

    // skip: QA #148 — en 23B·07 el botón «+ Agendar» no tiene relleno horizontal: el texto toca el
    // borde del botón (captura 148_e07_412_1.0x.png).
    probar(
      'el botón «+ Agendar» del vacío (23B·07) deja aire entre el texto y el borde',
      (tester) async {
        await llegarA(tester, Estado148.e07, tamano: telefonoGrande);

        final boton = tester.getRect(find.widgetWithText(OutlinedButton, '+ Agendar'));
        final texto = tester.getRect(
          find.descendant(of: find.byType(OutlinedButton), matching: find.text('+ Agendar')),
        );
        expect(boton.width - texto.width, greaterThanOrEqualTo(24));
      },
      skip: !verHallazgos,
    );
  });
}
