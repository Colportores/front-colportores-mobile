// QA de #432 (ronda 3): «Así quedó la venta» (42B·01D-01G) cuando «Poner fecha» o «Cambiar» no
// puede guardar la cita. El aviso va dentro de la tarjeta: matriz 360×640 / 412×915 × 1,0 / 2,0 con
// las fuentes reales, guías de toque y de etiqueta, región viva, que nada quede trabado y que el
// cierre siga diciendo la verdad al volver (la cobranza con la que se abrió). Capturas con
// `--dart-define=QA_CAPTURAS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_cuando_cobrar.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_venta_432_arnes.dart';

Agenda _cita(DateTime fecha) => Agenda(
  id: 'ag-1',
  espacioId: 'esp-1',
  espacioPersonaId: 'ep-1',
  tipo: TipoAgenda.cobranza,
  fechaProgramada: fecha,
  colportorId: 'col-1',
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
    createdBy: 'col-1',
  ),
);

const _aviso = 'No pudimos agendar el cobro. Probá de nuevo.';

void main() {
  usarFuentesReales = true;
  CobranzaDeLaVenta? quedo;

  setUp(() => quedo = null);

  Future<void> montar(
    WidgetTester tester, {
    Size tamano = telefonoChico,
    double escala = 1,
    CobranzaDeLaVenta cobranza = const CobranzaSinFecha(),
    Future<Agenda?> Function(Agenda)? alCambiar,
    Future<CobranzaDeLaVenta> Function()? alPonerFecha,
    String persona = 'Pedro Gómez',
  }) async {
    await cargarFuentes(tester);
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => quedo = await AsiQuedoLaVentaPage.abrir(
                context,
                AsiQuedoLaVentaPage(
                  numeroTalonario: '0039',
                  persona: persona,
                  direccion: 'Avenida General Rivera esquina Doctor Luis Alberto de Herrera 3307',
                  descripcion: 'Colección de 3 libros',
                  totalCentavos: 300000,
                  entrega: EntregaDelCierre.completa,
                  cobradoCentavos: 220000,
                  saldoCentavos: 80000,
                  cobranza: cobranza,
                  alCambiar: alCambiar,
                  alPonerFecha: alPonerFecha,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  for (final tamano in tamanos) {
    for (final escala in escalas) {
      final etiqueta = '${tamano.width.toInt()}x${tamano.height.toInt()} x$escala';

      testWidgets('«Poner fecha» falla ($etiqueta): sin overflow, aviso a la vista y guías', (
        tester,
      ) async {
        final h = tester.ensureSemantics();
        await montar(
          tester,
          tamano: tamano,
          escala: escala,
          alPonerFecha: () async => const CobranzaNoAgendada(),
        );

        await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));
        await tester.ensureVisible(find.byKey(ClavesCierreDeVenta.fallaCobranza));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(_aviso), findsOneWidget);
        expect(find.byKey(ClavesCierreDeVenta.fallaCobranza).hitTestable(), findsOneWidget);
        // El texto no queda cortado: cabe en el ancho de la pantalla.
        final r = tester.getRect(find.text(_aviso));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(tamano.width));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await capturar(tester, 'cierre_falla_${tamano.width.toInt()}_x$escala');
        h.dispose();
      });
    }
  }

  testWidgets('el aviso de la falla es una región viva con el texto', (tester) async {
    final h = tester.ensureSemantics();
    await montar(tester, alPonerFecha: () async => const CobranzaNoAgendada());

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));

    final nodo = tester.getSemantics(find.text(_aviso));
    expect(nodo.label, contains('No pudimos agendar el cobro'));
    expect(nodo.flagsCollection.isLiveRegion, isTrue);
    h.dispose();
  });

  testWidgets('«Cambiar» con la cita que falla: aviso en la tarjeta, la fecha vieja sigue', (
    tester,
  ) async {
    await montar(
      tester,
      cobranza: CobranzaAgendada(_cita(DateTime(2026, 10, 24, 12, 30))),
      alCambiar: (a) async => throw StateError('no se pudo'),
    );

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));

    expect(tester.takeException(), isNull);
    expect(find.text(_aviso), findsOneWidget);
    expect(find.text('SÁB 24/10 · 12:30'), findsOneWidget);
    await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
    expect(quedo, isA<CobranzaAgendada>());
  });

  testWidgets('dos toques seguidos con la cita demorada: una sola vez, y el botón vuelve', (
    tester,
  ) async {
    var llamadas = 0;
    final compuerta = Completer<CobranzaDeLaVenta>();
    await montar(
      tester,
      alPonerFecha: () {
        llamadas++;
        return compuerta.future;
      },
    );

    await tester.ensureVisible(find.byKey(ClavesCierreDeVenta.accionCobranza));
    await tester.tap(find.byKey(ClavesCierreDeVenta.accionCobranza));
    await tester.pump();
    await tester.tap(find.byKey(ClavesCierreDeVenta.accionCobranza), warnIfMissed: false);
    await tester.pump();
    expect(llamadas, 1);

    compuerta.complete(const CobranzaNoAgendada());
    await tester.pumpAndSettle();

    expect(find.text(_aviso), findsOneWidget);
    // Reintento: el aviso se va mientras guarda y la tarjeta vuelve a responder.
    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));
    expect(llamadas, 2);
  });

  testWidgets(
    'falla, reintento que elige día y vuelve: el aviso se va y el cierre devuelve la cita',
    (tester) async {
      var n = 0;
      await montar(
        tester,
        alPonerFecha: () async => ++n == 1
            ? const CobranzaNoAgendada()
            : CobranzaAgendada(_cita(DateTime(2026, 10, 25, 9))),
      );

      await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));
      expect(find.text(_aviso), findsOneWidget);
      await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));

      expect(find.text(_aviso), findsNothing);
      expect(find.text('DOM 25/10 · 09:00'), findsOneWidget);
      await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
      expect(quedo, isA<CobranzaAgendada>());
    },
  );

  testWidgets('falla y se vuelve sin reintentar: el cierre devuelve «sin fecha», no una cita', (
    tester,
  ) async {
    await montar(tester, alPonerFecha: () async => const CobranzaNoAgendada());

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));
    await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));

    expect(quedo, isA<CobranzaSinFecha>());
  });
}
