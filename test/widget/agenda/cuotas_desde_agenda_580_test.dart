// HU-COB-004 / issue #580 — «Ver las cuotas» en el detalle de una cobranza de cuota (vista 23 C →
// vista 30 A, 30A-06 de `00 Navegacion`: «Notificación o agenda de cobranza»): solo en una cobranza
// con su venta y su monto previsto, con el mismo texto que en el cobro, y los casos límite (doble
// toque, falla a mitad, volver y reentrar, texto 2.0).
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuotas_arnes.dart';
import '../../helpers/cuotas_desde_agenda_arnes.dart';
import '../../helpers/detalle_agenda_arnes.dart';

void main() {
  final botonCuotas = find.byKey(ClavesDetalleAgenda.verLasCuotas);

  group('Detalle de una cobranza de cuota · «Ver las cuotas»', () {
    testWidgets(
      'dado el detalle de una cobranza que es cuota, cuando se abre, entonces ofrece «Ver las cuotas»',
      (tester) async {
        await montarDetalleDeCuota(tester);

        expect(find.text('Cobranza'), findsOneWidget);
        expect(botonCuotas, findsOneWidget);
        expect(find.text('Ver las cuotas'), findsOneWidget);
        // Las salidas de siempre siguen donde estaban.
        expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      },
    );

    final sinAcceso = {
      'una cobranza sin venta ni monto': agendaDelDetalle(tipo: TipoAgenda.cobranza),
      'una cobranza con venta y sin monto previsto': agendaDelDetalle(
        tipo: TipoAgenda.cobranza,
        ventaId: 'v-1',
      ),
      'una cobranza con monto previsto y sin venta': agendaDelDetalle(
        tipo: TipoAgenda.cobranza,
        montoPrevistoCentavos: 83300,
      ),
      'una entrevista con venta y monto': agendaDelDetalle(
        ventaId: 'v-1',
        montoPrevistoCentavos: 83300,
      ),
    };
    for (final MapEntry(key: caso, value: agenda) in sinAcceso.entries) {
      testWidgets('dado $caso, entonces no hay acceso a las cuotas', (tester) async {
        await montarDetalleDeCuota(tester, agenda: agenda);
        expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
        expect(botonCuotas, findsNothing);
      });
    }

    testWidgets('cuando se toca, abre las cuotas de ESA venta y al volver el detalle sigue', (
      tester,
    ) async {
      await montarDetalleDeCuota(tester);

      await tester.tap(botonCuotas);
      await asentarDetalle(tester);

      expect(paginaLista, findsOneWidget);
      expect(find.text('PLAN · 3 CUOTAS SEMANALES'), findsOneWidget);
      expect(find.text('VENTA 0042'), findsOneWidget);

      await tester.tap(volverDeCuotas);
      await asentarDetalle(tester);

      expect(paginaLista, findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
      expect(botonCuotas, findsOneWidget);
    });

    testWidgets(
      'dado un doble toque (dos taps sin fotograma), entonces se abre una sola pantalla de cuotas',
      (tester) async {
        await montarDetalleDeCuota(tester);

        await tester.tap(botonCuotas);
        await tester.tap(botonCuotas, warnIfMissed: false);
        await asentarDetalle(tester);
        expect(paginaLista, findsOneWidget);

        await tester.tap(volverDeCuotas);
        await asentarDetalle(tester);

        // Con una sola pantalla de cuotas, un volver deja el detalle a la vista.
        expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
        expect(paginaLista, findsNothing);
      },
    );

    testWidgets(
      'dado que no se pudieron leer las cuotas, entonces la pantalla lo dice, se vuelve y el acceso '
      'sigue habilitado',
      (tester) async {
        final arnes = await montarDetalleDeCuota(tester);
        arnes.plan.fallaAlLeer = true;

        await tester.tap(botonCuotas);
        await asentarDetalle(tester);
        expect(find.text('No pudimos leer las cuotas guardadas en tu teléfono.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);

        await tester.tap(volverDeCuotas);
        await asentarDetalle(tester);
        arnes.plan.fallaAlLeer = false;

        await tester.tap(botonCuotas);
        await asentarDetalle(tester);
        expect(find.text('PLAN · 3 CUOTAS SEMANALES'), findsOneWidget);
      },
    );

    testWidgets('al volver de las cuotas el detalle vuelve a leer la agenda del teléfono', (
      tester,
    ) async {
      final arnes = await montarDetalleDeCuota(tester);
      final antes = arnes.detalle.repo.lecturas;

      await tester.tap(botonCuotas);
      await asentarDetalle(tester);
      await tester.tap(volverDeCuotas);
      await asentarDetalle(tester);

      expect(arnes.detalle.repo.lecturas, antes + 1);
    });

    for (final estado in [EstadoAgenda.cumplida, EstadoAgenda.cancelada]) {
      testWidgets('una cobranza $estado también deja ver las cuotas, sin las demás salidas', (
        tester,
      ) async {
        await montarDetalleDeCuota(tester, agenda: agendaDeCuota(estado: estado));
        expect(botonCuotas, findsOneWidget);
        expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
      });
    }

    testWidgets('con el texto al 200 % y 320 dp el acceso se ve entero y se puede tocar', (
      tester,
    ) async {
      await montarDetalleDeCuota(tester, escala: 2, tamano: const Size(320, 568));

      await tester.ensureVisible(botonCuotas);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(botonCuotas).height, greaterThanOrEqualTo(48));

      await tester.tap(botonCuotas);
      await asentarDetalle(tester);
      expect(paginaLista, findsOneWidget);
    });
  });
}
