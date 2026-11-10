// «Así quedó la venta» (vista 42, 42B·01D a 42B·01G; #432): el cierre único de la venta, solo. El
// recorrido con la entrevista está en `agenda/flujo_entrevista_venta_428_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_cuando_cobrar.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Agenda _cita(DateTime fecha, {String id = 'ag-1'}) => Agenda(
  id: id,
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

void main() {
  CobranzaDeLaVenta? quedo;

  setUp(() => quedo = null);

  Future<void> montar(
    WidgetTester tester, {
    EntregaDelCierre entrega = EntregaDelCierre.completa,
    int total = 300000,
    int cobrado = 0,
    int saldo = 300000,
    CobranzaDeLaVenta cobranza = const CobranzaSinFecha(),
    Future<Agenda?> Function(Agenda)? alCambiar,
    Future<CobranzaDeLaVenta> Function()? alPonerFecha,
    String persona = 'Pedro Gómez',
    double escala = 1,
    Size tamano = const Size(390, 844),
  }) async {
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
                  direccion: 'Grecia 3307',
                  descripcion: 'Colección de 1 libro',
                  totalCentavos: total,
                  entrega: entrega,
                  cobradoCentavos: cobrado,
                  saldoCentavos: saldo,
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

  testWidgets('42B·01D: entregada y pagada, «Venta completa» y sin tarjeta de cobranza', (
    tester,
  ) async {
    await montar(tester, cobrado: 300000, saldo: 0, cobranza: const SinSaldoQueCobrar());

    expect(find.text('VENTA 0039'), findsOneWidget);
    expect(find.text('Así quedó la venta'), findsOneWidget);
    expect(find.text('Pedro Gómez · Grecia 3307'), findsOneWidget);
    expect(find.text('Colección de 1 libro'), findsOneWidget);
    expect(find.text('✓ Entregada hoy'), findsOneWidget);
    expect(find.text(r'✓ $ 3.000 en efectivo'), findsOneWidget);
    expect(find.byKey(ClavesCierreDeVenta.completa), findsOneWidget);
    expect(find.byKey(ClavesCierreDeVenta.tarjetaCobranza), findsNothing);
  });

  testWidgets('42B·01E: con cobro parcial y cobranza agendada, la tarjeta con fecha y «Cambiar»', (
    tester,
  ) async {
    await montar(
      tester,
      cobrado: 220000,
      saldo: 80000,
      cobranza: CobranzaAgendada(_cita(DateTime(2026, 10, 24, 12, 30))),
      alCambiar: (a) async => null,
    );

    expect(find.text(r'✓ $ 2.200 en efectivo'), findsOneWidget);
    expect(find.text('SÁB 24/10 · 12:30'), findsOneWidget);
    expect(find.text('Cobranza agendada · Pedro'), findsOneWidget);
    expect(find.text(r'Saldo $ 800 · en Grecia 3307'), findsOneWidget);
    expect(find.text('Cambiar'), findsOneWidget);
    expect(find.byKey(ClavesCierreDeVenta.completa), findsNothing);
  });

  testWidgets('42B·01G: sin fecha, «SIN FECHA» y «Poner fecha»; entrega de otro día', (
    tester,
  ) async {
    await montar(
      tester,
      entrega: EntregaDelCierre.otroDia,
      saldo: 120000,
      alPonerFecha: () async => const CobranzaSinFecha(),
    );

    expect(find.text('⇢ Otro día'), findsOneWidget);
    expect(find.text('Sin cobrar'), findsOneWidget);
    expect(find.text('SIN FECHA'), findsOneWidget);
    expect(find.text(r'Saldo $ 1.200 · queda en tus cobranzas, sin día'), findsOneWidget);
    expect(find.text('Poner fecha'), findsOneWidget);
  });

  testWidgets('«Cambiar» reemplaza la tarjeta con la cita nueva y la devuelve al salir', (
    tester,
  ) async {
    final nueva = _cita(DateTime(2026, 10, 27, 9), id: 'ag-1');
    await montar(
      tester,
      saldo: 80000,
      cobranza: CobranzaAgendada(_cita(DateTime(2026, 10, 24, 12, 30))),
      alCambiar: (a) async => nueva,
    );

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));
    expect(find.text('MAR 27/10 · 09:00'), findsOneWidget);
    await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));

    expect(
      (quedo! as CobranzaAgendada).agenda.fechaProgramada.toLocal(),
      DateTime(2026, 10, 27, 9),
    );
  });

  testWidgets('«Poner fecha» que agenda cambia «SIN FECHA» por la cita', (tester) async {
    await montar(
      tester,
      saldo: 80000,
      alPonerFecha: () async => CobranzaAgendada(_cita(DateTime(2026, 10, 25, 10))),
    );

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));

    expect(find.text('SIN FECHA'), findsNothing);
    expect(find.text('DOM 25/10 · 10:00'), findsOneWidget);
  });

  testWidgets('mientras «Cambiar» está en vuelo, «Volver al mapa» y otro toque no hacen nada', (
    tester,
  ) async {
    final espera = Completer<Agenda?>();
    var llamadas = 0;
    await montar(
      tester,
      saldo: 80000,
      cobranza: CobranzaAgendada(_cita(DateTime(2026, 10, 24, 12, 30))),
      alCambiar: (a) {
        llamadas++;
        return espera.future;
      },
    );

    await tester.tap(find.byKey(ClavesCierreDeVenta.accionCobranza));
    await tester.pump();
    await tester.tap(find.byKey(ClavesCierreDeVenta.accionCobranza), warnIfMissed: false);
    await tester.tap(find.byKey(ClavesCierreDeVenta.volver), warnIfMissed: false);
    await tester.pump();

    expect(llamadas, 1);
    expect(find.byKey(ClavesCierreDeVenta.pagina), findsOneWidget);
    espera.complete(null);
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
    expect(quedo, isA<CobranzaAgendada>());
  });

  testWidgets('si «Cambiar» falla, la tarjeta queda como estaba y nada queda trabado', (
    tester,
  ) async {
    await montar(
      tester,
      saldo: 80000,
      cobranza: CobranzaAgendada(_cita(DateTime(2026, 10, 24, 12, 30))),
      alCambiar: (a) async => throw StateError('sin base'),
    );

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));

    expect(tester.takeException(), isNull);
    expect(find.text('SÁB 24/10 · 12:30'), findsOneWidget);
    expect(find.byKey(ClavesCierreDeVenta.fallaCobranza), findsOneWidget);
    await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
    expect(quedo, isA<CobranzaAgendada>());
  });

  testWidgets(
    '«Poner fecha» con la cita que no se guarda: lo dice en la tarjeta, que sigue sin fecha',
    (tester) async {
      var intentos = 0;
      await montar(
        tester,
        saldo: 80000,
        alPonerFecha: () async {
          intentos++;
          return intentos == 1
              ? const CobranzaNoAgendada()
              : CobranzaAgendada(_cita(DateTime(2026, 10, 25, 10)));
        },
      );

      await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));

      expect(find.text('No pudimos agendar el cobro. Probá de nuevo.'), findsOneWidget);
      expect(find.text('SIN FECHA'), findsOneWidget);
      // Nada queda trabado: se puede reintentar, y al agendar el aviso se va.
      await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));
      expect(intentos, 2);
      expect(find.byKey(ClavesCierreDeVenta.fallaCobranza), findsNothing);
      expect(find.text('DOM 25/10 · 10:00'), findsOneWidget);
      await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
      expect(quedo, isA<CobranzaAgendada>());
    },
  );

  testWidgets('«Poner fecha» que vuelve sin elegir (sigue sin fecha) no muestra ningún aviso', (
    tester,
  ) async {
    await montar(tester, saldo: 80000, alPonerFecha: () async => const CobranzaSinFecha());

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));

    expect(find.byKey(ClavesCierreDeVenta.fallaCobranza), findsNothing);
    expect(find.text('SIN FECHA'), findsOneWidget);
  });

  testWidgets('el aviso de la falla en la tarjeta entra a 320×568 con la letra al 200 %', (
    tester,
  ) async {
    await montar(
      tester,
      saldo: 80000,
      escala: 2,
      tamano: const Size(320, 568),
      alPonerFecha: () async => const CobranzaNoAgendada(),
    );

    await tocar(tester, find.byKey(ClavesCierreDeVenta.accionCobranza));
    await tester.ensureVisible(find.byKey(ClavesCierreDeVenta.fallaCobranza));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(ClavesCierreDeVenta.fallaCobranza).hitTestable(), findsOneWidget);
  });

  testWidgets('el atrás del sistema hace lo mismo que «Volver al mapa»', (tester) async {
    await montar(tester, saldo: 80000);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(ClavesCierreDeVenta.pagina), findsNothing);
    expect(quedo, isA<CobranzaSinFecha>());
  });

  testWidgets('dos toques en «Volver al mapa» cierran una sola pantalla', (tester) async {
    await montar(tester, saldo: 80000);

    await tester.tap(find.byKey(ClavesCierreDeVenta.volver));
    await tester.tap(find.byKey(ClavesCierreDeVenta.volver), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('botones de 48 dp con etiqueta y contraste', (tester) async {
    final semantica = tester.ensureSemantics();
    await montar(
      tester,
      saldo: 80000,
      cobranza: CobranzaAgendada(_cita(DateTime(2026, 10, 24, 12, 30))),
      alCambiar: (a) async => null,
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantica.dispose();
  });

  for (final tamano in [const Size(320, 568), const Size(412, 915)]) {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'a ${tamano.width.toInt()}×${tamano.height.toInt()} y letra $escala con un nombre larguísimo '
        'no desborda y llega a «Cambiar» y al botón',
        (tester) async {
          await montar(
            tester,
            persona: 'María de los Ángeles Fernández de la Cruz y Sotomayor Echeverría',
            total: 999999999,
            cobrado: 1,
            saldo: 999999998,
            cobranza: CobranzaAgendada(_cita(DateTime(2026, 10, 24, 12, 30))),
            alCambiar: (a) async => null,
            escala: escala,
            tamano: tamano,
          );

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(ClavesCierreDeVenta.accionCobranza));
          await tester.pumpAndSettle();
          expect(find.byKey(ClavesCierreDeVenta.accionCobranza).hitTestable(), findsOneWidget);
          expect(find.byKey(ClavesCierreDeVenta.volver).hitTestable(), findsOneWidget);
        },
      );
    }
  }
}
