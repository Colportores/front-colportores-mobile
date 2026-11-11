// QA del PR #678 (HU-VEN-003, #433) sobre la cita de ENTREGA en la Agenda (vista 23, 23B/23C): lo que
// el QA de #536 (`qa_vista23_entrega_433_*`) no cubría porque su arnés no engancha «Registrar
// resultado» como lo hace `main.dart`, y los artboards 23C·03, 23C·05, 23C·06 y 23C·07 con una agenda
// de tipo ENTREGA, más la fila vencida y los filtros por tipo.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/modificar_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/detalle_agenda_arnes.dart';
import '../../helpers/qa_vista23_409_arnes.dart'
    show modificar409, sinTextoCortado409, subirHora409, tocar409;
import '../../helpers/qa_vista23_entrega_433_arnes.dart';
import '../../helpers/qa_vista23_entrega_678_arnes.dart';

DetalleDeAgenda _entrega({EstadoAgenda estado = EstadoAgenda.programada}) => DetalleDeAgenda(
  agenda: agendaDelDetalle(tipo: TipoAgenda.entrega, estado: estado, ventaId: 'ven-1'),
);

Future<ArnesDetalle> _detalle(
  WidgetTester tester, {
  EstadoAgenda estado = EstadoAgenda.programada,
  bool conRegistrar = false,
  Size tamano = const Size(360, 640),
  double escala = 1,
}) async {
  final a = await montarDetalle(
    tester,
    detalle: _entrega(estado: estado),
    conRegistrar: conRegistrar,
    tamano: tamano,
    escala: escala,
    abrir: false,
  );
  await abrirDetalle(tester);
  return a;
}

void main() {
  group('23C·01 detalle de una cita de entrega: textos del canvas', () {
    testWidgets(
      'dice «Entrega», el estado, el cuándo, la franja y ofrece «Modificar» y «Cancelar agenda»',
      (tester) async {
        await _detalle(tester);

        expect(find.byType(DetalleAgendaPage), findsOneWidget);
        expect(find.text('Entrega'), findsWidgets);
        expect(find.text('Programada'), findsOneWidget);
        expect(find.text('Primera tarde'), findsOneWidget);
        expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
        expect(find.text('Cancelar agenda'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    // QA #433: con el destino de «Registrar resultado» enganchado (como en `main.dart:303`) el
    // detalle de una ENTREGA ofrece «Registrar resultado», que abre «¿Qué pasó?» (Venta, Entrevista
    // hecha, Rechazó…) y, al guardar, deja la cita en CUMPLIDA/NO_CUMPLIDA con la visita
    // (`agenda_local_data_source_drift.dart:303-317`) sin entregar nada: la entrega sigue pendiente
    // sin cita ni aviso. La fila de la lista, en cambio, no ofrece «Registrar» a una entrega.
    testWidgets(
      'el detalle de una entrega no ofrece «Registrar resultado» (es el flujo de una visita)',
      (tester) async {
        await _detalle(tester, conRegistrar: true);

        expect(
          find.byKey(ClavesDetalleAgenda.registrar),
          findsNothing,
          reason: 'la entrega se cumple con «Entregado hoy», no con el resultado de una visita',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    // Fix del bloqueante de QA de #678: «Registrar resultado» solo para las citas de visita y de
    // cobranza; la entrega espera al flujo de #435 (entrega para otro día).
    for (final (tipo, ofrece) in [
      (TipoAgenda.entrega, false),
      (TipoAgenda.entrevista, true),
      (TipoAgenda.cobranza, true),
    ]) {
      testWidgets('con el destino enganchado, una cita ${tipo.codigo} '
          '${ofrece ? 'ofrece' : 'no ofrece'} «Registrar resultado» y deja «Modificar» a mano', (
        tester,
      ) async {
        await montarDetalle(
          tester,
          detalle: DetalleDeAgenda(
            agenda: agendaDelDetalle(tipo: tipo, ventaId: 'ven-1'),
          ),
          conRegistrar: true,
          abrir: false,
        );
        await abrirDetalle(tester);

        expect(find.byKey(ClavesDetalleAgenda.registrar), ofrece ? findsOneWidget : findsNothing);
        expect(find.text('Registrar resultado'), ofrece ? findsOneWidget : findsNothing);
        expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
        expect(find.text('Cancelar agenda'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('sin el destino enganchado, «Modificar» y «Cancelar agenda» siguen a mano', (
      tester,
    ) async {
      await _detalle(tester, conRegistrar: false);

      expect(find.byKey(ClavesDetalleAgenda.registrar), findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('23C·06 una entrega ya cumplida no se modifica ni se cancela', () {
    testWidgets('dice que ya tiene resultado y no ofrece «Modificar» ni «Cancelar agenda»', (
      tester,
    ) async {
      await _detalle(tester, estado: EstadoAgenda.cumplida, conRegistrar: true);

      expect(find.byKey(ClavesDetalleAgenda.avisoCerrada), findsOneWidget);
      expect(
        find.text('Esta visita ya tiene resultado: no se puede modificar ni cancelar.'),
        findsOneWidget,
      );
      expect(find.text('Cumplida'), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.registrar), findsNothing);
      expect(find.text('Cancelar agenda'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('23C·03 y 23C·07 modificar la hora de una cita de entrega', () {
    Future<ArnesDetalle> abrirModificar(WidgetTester tester, {double escala = 1}) async {
      final a = await _detalle(tester, escala: escala);
      await tocar409(tester, modificar409);
      return a;
    }

    testWidgets('guardar con otra hora avisa «Guardado. El recordatorio pasó a las …»', (
      tester,
    ) async {
      final a = await abrirModificar(tester);
      await subirHora409(tester, 6);

      await tocar409(tester, find.byKey(ClavesModificarAgenda.guardar));

      expect(a.repo.recibidos.single.tipo, TipoAgenda.entrega);
      expect(find.textContaining('Guardado. El recordatorio pasó a las'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'si falla al guardar: dice qué pasó, conserva la hora y «Reintentar» guarda una vez',
      (tester) async {
        final a = await abrirModificar(tester);
        a.repo.fallas.add(const FailureInesperado());
        await subirHora409(tester, 6);

        await tocar409(tester, find.byKey(ClavesModificarAgenda.guardar));

        expect(
          find.text('No pudimos guardar el cambio. La agenda sigue como estaba.'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
        final seleccion = tester.widget<SegmentedButton<TipoAgenda>>(
          find.byType(SegmentedButton<TipoAgenda>),
        );
        expect(seleccion.selected, {
          TipoAgenda.entrega,
        }, reason: 'el tipo no se pierde tras el error');

        await tocar409(tester, find.byKey(ClavesModificarAgenda.guardar));

        expect(a.repo.recibidos, hasLength(2), reason: 'el reintento guarda una vez más, no dos');
        expect(a.repo.recibidos.last.tipo, TipoAgenda.entrega);
        expect(find.byType(ModificarAgendaPage), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('un segundo toque a «Guardar cambios» mientras guarda no guarda dos veces', (
      tester,
    ) async {
      final a = await abrirModificar(tester);
      await subirHora409(tester, 6);
      a.repo.compuerta = Completer<void>();

      await tester.ensureVisible(find.byKey(ClavesModificarAgenda.guardar));
      await tester.tap(find.byKey(ClavesModificarAgenda.guardar));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(ClavesModificarAgenda.guardar), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('Guardando…'), findsOneWidget);
      a.repo.compuerta!.complete();
      await asentarDetalle(tester);
      expect(a.repo.recibidos, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('23C·04/05 cancelar una entrega cuando el aviso no se puede borrar', () {
    testWidgets('queda cancelada y dice que el recordatorio puede sonar igual', (tester) async {
      final m = await montar455(tester, tipo: TipoAgenda.entrega, recordatorioSeQueda: true);
      await abrirHoja455(tester);

      await confirmar455Tocar(tester);

      expect(m.repo.canceladas, ['ag-1']);
      expect(find.text(canceladaSinAviso455), findsOneWidget);
      expect(tester.takeException(), isNull);
      await desmontar455(tester);
    });

    testWidgets(
      'con el filtro «Canceladas» la cita se ve tachada, con su rótulo y sin «Registrar»',
      (tester) async {
        final m = await llegarA433(tester, Estado433.cancelada);
        // La lista lee en vivo: la cita ya cancelada solo se ve con el filtro de estado.
        await filtrarCanceladas455(tester);

        final h = tester.ensureSemantics();
        final fila = find.byType(FilaAgenda);
        expect(fila, findsOneWidget);
        // Como en 23B·05, la etiqueta de una cerrada es su estado; el tipo lo lee el lector.
        expect(find.descendant(of: fila, matching: find.text('Cancelada')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(r'Entrega\. .*Cancelada')), findsOneWidget);
        expect(find.byKey(const Key('agenda_registrar_ag-1')), findsNothing);
        expect(m.repo.canceladas, ['ag-1']);
        h.dispose();
        await desmontar455(tester);
      },
    );
  });

  group('23B filtros por tipo con una cita de entrega', () {
    testWidgets(
      '«Todas» la muestra; «Cobranzas» y «Entrevistas» no, y «Limpiar filtros» la devuelve',
      (tester) async {
        await llegarA433(tester, Estado433.lista);
        expect(find.byType(FilaAgenda), findsOneWidget);

        await tester.tap(find.text('Cobranzas'));
        await tester.pumpAndSettle();
        expect(find.byType(FilaAgenda), findsNothing);
        expect(find.text('Ninguna agenda con estos filtros'), findsOneWidget);

        await tester.tap(find.text('Entrevistas'));
        await tester.pumpAndSettle();
        expect(find.byType(FilaAgenda), findsNothing);

        await tester.tap(find.text('Limpiar filtros'));
        await tester.pumpAndSettle();
        expect(find.byType(FilaAgenda), findsOneWidget);
        await desmontar455(tester);
      },
    );
  });

  group('23B·02 una entrega con la hora vencida', () {
    Future<Montaje455> vencida(
      WidgetTester tester, {
      Size tamano = chico455,
      double escala = 1,
    }) async {
      final m = await llegarA433(tester, Estado433.lista, tamano: tamano, escala: escala);
      m.consulta.emitir([
        itemAgenda(
          'ag-1',
          DateTime(2026, 10, 23, 11),
          tipo: TipoAgenda.entrega,
          nombre: 'María',
          apellido: 'Fernández',
          calle: 'Mataojo',
          numero: '2044',
          espacioId: 'esp-1',
        ),
      ]);
      await asentarDetalle(tester);
      return m;
    }

    testWidgets('la fila abre el detalle (hay a dónde ir) y no ofrece «Registrar»', (tester) async {
      await vencida(tester);

      expect(find.byType(FilaAgenda), findsOneWidget);
      expect(find.byKey(const Key('agenda_registrar_ag-1')), findsNothing);
      await entrar455(tester);
      expect(find.byType(DetalleAgendaPage), findsOneWidget);
      await desmontar455(tester);
    });

    // QA #433: una entrega no ofrece «Registrar» (el detalle no registra «Entregado hoy» hasta #435),
    // así que su fila vencida dice solo «Pasó la hora», sin «registrá qué pasó» (las entrevistas
    // siguen como 23B·02).
    testWidgets(
      'la fila vencida de una entrega dice solo «Pasó la hora», sin indicación sin acción',
      (tester) async {
        await vencida(tester);

        expect(find.text('Pasó la hora'), findsOneWidget);
        expect(find.textContaining('registrá qué pasó'), findsNothing);
        expect(find.byKey(const Key('agenda_registrar_ag-1')), findsNothing);
        await desmontar455(tester);
      },
    );
  });

  group('sin overflow ni texto cortado en los estados nuevos (capturas con QA_CAPTURAS)', () {
    for (final tamano in [chico455, grande455]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado678.values) {
          testWidgets('${estado.rotulo} · ${sufijo455(tamano, escala)}', (tester) async {
            await llegarA678(tester, estado, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull);
            sinTextoCortado409(tester);
            await capturar433(tester, '678_${estado.name}_${sufijo455(tamano, escala)}');
            await tester.pumpWidget(const SizedBox.shrink());
          });
        }
      }
    }
  });
}
