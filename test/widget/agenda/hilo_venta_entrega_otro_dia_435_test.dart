// #435 en el hilo de la venta (vista 42, 42B·01): «Entregar otro día» de 27A·14 abre 27C·01; sin
// entregar nada la app pide la fecha de la entrega antes de «¿Cuándo volvés a cobrar?» (01F, 01G); el
// cierre muestra «Entrega agendada» y el aviso del mapa la nombra.
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/cuando_cobrar_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_entrega.dart'
    show FilaDeEntrega;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart' show diferidaPara;
import '../../helpers/entrega_falsos.dart' show EntornoDeEntrega, entregaDe;
import '../../helpers/qa_vista39_venta_428_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';

const _paginaOtroDia = Key('otro_dia_pagina');

void main() {
  late Arnes428 a;
  late EntornoDeEntrega entrega;

  setUp(() => a = Arnes428());

  Future<void> hastaVentaRegistrada(WidgetTester tester) async {
    entrega = EntornoDeEntrega();
    entrega.entregas.respuestaDeDiferir = diferidaPara(DateTime(2026, 10, 31, 16, 30));
    a.montaje.extra.addAll([
      ...entrega.overrides,
      cobrarDespuesDeLaVentaProvider.overrideWithValue((contexto) async => false),
    ]);
    await a.montar(tester);
    await a.hastaLaVenta(tester);
    await a.armarLaVenta(tester);
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await tester.pumpAndSettle();
  }

  /// Elige un día en «Fecha prevista» de 27C·01 y guarda.
  Future<void> elegirFechaYGuardar(WidgetTester tester) async {
    await tocar(tester, find.byKey(const Key('entrega_campo_fecha')));
    await tester.ensureVisible(find.byKey(ClavesAgendarVisita.dia(1)));
    await tester.tap(find.byKey(ClavesAgendarVisita.dia(1)));
    await tester.pump();
    await tester.ensureVisible(find.byKey(ClavesAgendarVisita.hojaListo));
    await tester.tap(find.byKey(ClavesAgendarVisita.hojaListo));
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await tester.pumpAndSettle();
  }

  testWidgets('27A·14 ofrece «Entregar otro día» y lleva a 27C·01', (tester) async {
    await hastaVentaRegistrada(tester);

    expect(find.text(TextosVenta.entregarOtroDia), findsOneWidget);
    await tocar(tester, find.text(TextosVenta.entregarOtroDia));
    await tocar(tester, find.text(TextosVenta.continuar));
    await tester.pumpAndSettle();

    expect(find.byKey(_paginaOtroDia), findsOneWidget);
  });

  testWidgets('volver de 27C·01 sin guardar vuelve a «¿Y ahora?» sin agendar nada', (tester) async {
    await hastaVentaRegistrada(tester);
    await tocar(tester, find.text(TextosVenta.entregarOtroDia));
    await tocar(tester, find.text(TextosVenta.continuar));
    await tester.pumpAndSettle();

    await tocar(tester, find.byKey(const Key('venta_atras')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
    expect(entrega.entregas.diferidas, isEmpty);
  });

  testWidgets('42B·01G: «Terminar sin entregar ni cobrar» pide la fecha de la entrega y el cierre '
      'la muestra; el aviso del mapa la nombra', (tester) async {
    await hastaVentaRegistrada(tester);
    await tocar(tester, find.byKey(const Key('venta_terminar')));
    await tester.pumpAndSettle();

    expect(find.byKey(_paginaOtroDia), findsOneWidget);
    await elegirFechaYGuardar(tester);

    expect(entrega.entregas.diferidas, hasLength(1));
    // Sin aviso propio de 27C·01: lo dicen el cierre y el mapa.
    expect(find.textContaining('Entrega guardada para'), findsNothing);
    expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
    await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
    await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
    await tester.pumpAndSettle();

    expect(find.byKey(ClavesCierreDeVenta.tarjetaEntrega), findsOneWidget);
    expect(find.textContaining('Entrega agendada'), findsOneWidget);
    expect(find.text('SÁB 31/10'), findsOneWidget);
    expect(find.text(TextosCierreDeVenta.entregaOtroDia), findsOneWidget);

    await tocar(tester, find.byKey(ClavesCierreDeVenta.volver));
    await tester.pumpAndSettle();

    expect(find.textContaining('Entrega: sáb 31/10. Cobranza sin fecha.'), findsOneWidget);
  });

  testWidgets('la fecha de entrega se pide una sola vez: elegida en 27A·14, no vuelve a salir', (
    tester,
  ) async {
    await hastaVentaRegistrada(tester);
    await tocar(tester, find.text(TextosVenta.entregarOtroDia));
    await tocar(tester, find.text(TextosVenta.continuar));
    await tester.pumpAndSettle();
    await elegirFechaYGuardar(tester);

    expect(find.byKey(_paginaOtroDia), findsNothing);
    expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
    expect(entrega.entregas.diferidas, hasLength(1));
  });

  testWidgets('volver sin elegir la fecha que pide el hilo deja la venta sin entrega agendada', (
    tester,
  ) async {
    await hastaVentaRegistrada(tester);
    await tocar(tester, find.byKey(const Key('venta_terminar')));
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('venta_atras')));
    await tester.pumpAndSettle();

    expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
    await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
    await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
    await tester.pumpAndSettle();

    expect(find.byKey(ClavesCierreDeVenta.tarjetaEntrega), findsNothing);
    expect(entrega.entregas.diferidas, isEmpty);
  });

  /// 27A·14 «Entregar ahora» y 27B·01 registrada con algo que queda pendiente: una entrega parcial.
  Future<void> entregarUnaParte(WidgetTester tester) async {
    entrega.entregas.pendientesAlRegistrar = [
      entregaDe('e-resto', 'p-resto', pendiente: true, ventaId: 'v-1'),
    ];
    await tocar(tester, find.text(TextosVenta.entregarAhora));
    await tocar(tester, find.text(TextosVenta.continuar));
    await tester.pumpAndSettle();
    expect(find.byType(FilaDeEntrega), findsWidgets);
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await tester.pumpAndSettle();
  }

  group(
    'tras una entrega parcial se pide la fecha de lo que quedó (decisión del 10/11, P2 de #687)',
    () {
      testWidgets('27C·01 se abre antes de «¿Cuándo volvés a cobrar?» y el cierre la muestra', (
        tester,
      ) async {
        await hastaVentaRegistrada(tester);
        await entregarUnaParte(tester);

        expect(entrega.entregas.recibidas, hasLength(1));
        expect(find.byKey(_paginaOtroDia), findsOneWidget);
        expect(find.byKey(ClavesCuandoCobrar.pagina), findsNothing);
        await elegirFechaYGuardar(tester);

        expect(entrega.entregas.diferidas, hasLength(1));
        expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
        await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
        await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
        await tester.pumpAndSettle();

        expect(find.text(TextosCierreDeVenta.entregadaEnParte), findsOneWidget);
        expect(find.byKey(ClavesCierreDeVenta.tarjetaEntrega), findsOneWidget);
      });

      testWidgets('«atrás» en 27C·01 deja lo que quedó sin fecha y sigue a la pregunta', (
        tester,
      ) async {
        await hastaVentaRegistrada(tester);
        await entregarUnaParte(tester);

        await tocar(tester, find.byKey(const Key('venta_atras')));
        await tester.pumpAndSettle();

        expect(entrega.entregas.diferidas, isEmpty);
        expect(find.byKey(ClavesCuandoCobrar.pagina), findsOneWidget);
      });
    },
  );

  testWidgets('con la entrega ya agendada y el cobro cancelado, «¿Y ahora?» no vuelve a ofrecer '
      '«Entregar ahora» y el cierre no miente (revisión de #687)', (tester) async {
    await hastaVentaRegistrada(tester);
    await tocar(tester, find.text(TextosVenta.entregarOtroDia));
    await tocar(tester, find.text(TextosVenta.cobrarAhora));
    await tocar(tester, find.text(TextosVenta.continuar));
    await tester.pumpAndSettle();
    await elegirFechaYGuardar(tester);

    // El cobro devuelve «no cobré»: vuelve a 27A·14.
    expect(find.byKey(const Key('venta_registrada_pagina')), findsOneWidget);
    expect(find.text(TextosVenta.entregarAhora), findsNothing);
    expect(find.text(TextosVenta.entregarOtroDia), findsNothing);

    await tocar(tester, find.byKey(const Key('venta_terminar')));
    await tester.pumpAndSettle();
    expect(find.byKey(_paginaOtroDia), findsNothing);
    await tocar(tester, find.byKey(ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha)));
    await tocar(tester, find.byKey(ClavesCuandoCobrar.guardar));
    await tester.pumpAndSettle();

    expect(entrega.entregas.recibidas, isEmpty);
    expect(find.byKey(ClavesCierreDeVenta.tarjetaEntrega), findsOneWidget);
  });
}
