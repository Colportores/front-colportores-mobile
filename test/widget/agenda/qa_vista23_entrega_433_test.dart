// QA de la cita de ENTREGA en la Agenda (HU-VEN-003, #433): la fila de la lista, el detalle, «Modificar»
// y «Cancelar» con una agenda de tipo ENTREGA, en 360x640 y 412x915, con texto 1,0 y 2,0. Las capturas
// van a `.dart_tool/qa_capturas/` con `--dart-define=QA_CAPTURAS=true`; los hallazgos, con `skip:`.
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agenda.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/detalle_agenda_arnes.dart' show asentarDetalle;
import '../../helpers/qa_vista23_409_arnes.dart' show sinTextoCortado409, subirHora409;
import '../../helpers/qa_vista23_entrega_433_arnes.dart';

void main() {
  group('la fila de la entrega en la Agenda', () {
    testWidgets('lleva el rótulo «Entrega» y no ofrece «Registrar» desde la lista', (tester) async {
      await llegarA433(tester, Estado433.lista);

      final fila = find.byType(FilaAgenda);
      expect(fila, findsOneWidget);
      expect(find.descendant(of: fila, matching: find.text('Entrega')), findsOneWidget);
      expect(find.byKey(const Key('agenda_registrar_ag-1')), findsNothing);
      expect(tester.takeException(), isNull);
      await desmontar455(tester);
    });

    // skip: QA #433 — la fila de una cita ENTREGA lleva la insignia «Cobranza pendiente»
    testWidgets('la insignia de la casa no dice «Cobranza pendiente» en una cita de entrega', (
      tester,
    ) async {
      await llegarA433(tester, Estado433.lista);

      final insignia = tester.widget<InsigniaEstadoCasa>(
        find.descendant(of: find.byType(FilaAgenda), matching: find.byType(InsigniaEstadoCasa)),
      );

      expect(
        insignia.estado,
        isNot(EstadoCasa.cobranzaPendiente),
        reason:
            'la fila de una entrega se lee «${FormatoListaUbicaciones.estado(insignia.estado)}»',
      );
      await desmontar455(tester);
    }, skip: true);
  });

  group('el detalle de la entrega', () {
    testWidgets('dice «Entrega» como tipo y ofrece «Modificar»', (tester) async {
      await llegarA433(tester, Estado433.detalle);

      expect(find.byType(DetalleAgendaPage), findsOneWidget);
      expect(find.text('Entrega'), findsWidgets);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await desmontar455(tester);
    });
  });

  group('«Modificar» una cita de entrega', () {
    testWidgets('muestra el tipo «Entrega» elegido y no deja cambiarlo', (tester) async {
      await llegarA433(tester, Estado433.modificar);

      final selector = tester.widget<SegmentedButton<TipoAgenda>>(
        find.byType(SegmentedButton<TipoAgenda>),
      );
      expect(selector.selected, {TipoAgenda.entrega});
      expect(selector.onSelectionChanged, isNull, reason: 'el tipo de una entrega no se elige');
      expect(
        [for (final s in selector.segments) s.value],
        [TipoAgenda.entrevista, TipoAgenda.cobranza, TipoAgenda.entrega],
      );

      await tester.tap(find.text('Cobranza'), warnIfMissed: false);
      await tester.pump();
      expect(
        tester
            .widget<SegmentedButton<TipoAgenda>>(find.byType(SegmentedButton<TipoAgenda>))
            .selected,
        {TipoAgenda.entrega},
      );
      expect(tester.takeException(), isNull);
      await desmontar455(tester);
    });

    testWidgets('guardar con otra hora manda el tipo ENTREGA y no el de una entrevista', (
      tester,
    ) async {
      final m = await llegarA433(tester, Estado433.modificar);
      await subirHora409(tester, 6);

      await tester.ensureVisible(guardar433);
      await tester.tap(guardar433);
      await asentarDetalle(tester);

      expect(m.repo.recibidos, hasLength(1));
      expect(m.repo.recibidos.single.tipo, TipoAgenda.entrega);
      expect(tester.takeException(), isNull);
      await desmontar455(tester);
    });
  });

  group('el selector de tipo de una entrega con el texto al doble', () {
    for (final tamano in [chico455, grande455]) {
      // skip: QA #433 — con tres segmentos, a 2,0× «Entrevista», «Cobranza» y «Entrega» se parten a la mitad
      testWidgets('ninguna etiqueta se parte por la mitad · ${sufijo455(tamano, 2)}', (
        tester,
      ) async {
        await llegarA433(tester, Estado433.modificar, tamano: tamano, escala: 2);

        final partidas = <String>[];
        for (final e
            in find
                .descendant(
                  of: find.byType(SegmentedButton<TipoAgenda>),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          final texto = p.text.toPlainText();
          final renglones = p.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: texto.length),
          );
          if (renglones.length > 1) partidas.add(texto);
        }

        expect(partidas, isEmpty, reason: 'etiquetas en varios renglones: $partidas');
        await desmontar455(tester);
      }, skip: true);
    }
  });

  group('cancelar una cita de entrega', () {
    testWidgets('dado que abro «Cancelar agenda», la hoja dice los textos literales', (
      tester,
    ) async {
      await llegarA433(tester, Estado433.hoja);

      expect(find.descendant(of: hoja455, matching: find.text(tituloEntrega433)), findsOneWidget);
      expect(find.descendant(of: hoja455, matching: find.text(cuerpoEntrega433)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await desmontar455(tester);
    });

    testWidgets('cuando confirmo, queda cancelada y el aviso lo dice', (tester) async {
      final m = await llegarA433(tester, Estado433.cancelada);

      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(canceladaOk455), findsOneWidget);
      expect(tester.takeException(), isNull);
      await desmontar455(tester);
    });

    testWidgets('un segundo toque a «Cancelar» mientras guarda no cancela dos veces', (
      tester,
    ) async {
      final m = await llegarA433(tester, Estado433.hojaCancelando);

      await tester.tap(confirmar455, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));

      expect(m.repo.canceladas, ['ag-1']);
      m.repo.compuertaAlCancelar!.complete();
      await asentarDetalle(tester);
      await desmontar455(tester);
    });

    testWidgets('si falla al guardar, dice qué pasó y se puede reintentar', (tester) async {
      final m = await llegarA433(tester, Estado433.hojaError);

      expect(find.text(errorAlGuardar455), findsOneWidget);
      expect(tester.widget<FilledButton>(confirmar455).onPressed, isNotNull);

      await tester.ensureVisible(confirmar455);
      await tester.tap(confirmar455);
      await asentarDetalle(tester);

      expect(m.repo.canceladas, ['ag-1', 'ag-1']);
      await desmontar455(tester);
    });
  });

  group('sin overflow ni texto cortado en cada estado', () {
    for (final tamano in [chico455, grande455]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado433.values) {
          testWidgets('${estado.rotulo} · ${sufijo455(tamano, escala)}', (tester) async {
            await llegarA433(tester, estado, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull);
            sinTextoCortado409(tester);
            await capturar433(tester, '${estado.name}_${sufijo455(tamano, escala)}');
            await desmontar455(tester);
          });
        }
      }
    }
  });
}
