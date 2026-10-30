// QA de #428, ronda 2 (d8f68fde): 27A·14 «Venta registrada» entre la venta y «¿Cuándo volvés a
// cobrar?», «Cobrar ahora» y el aviso «Venta N guardada.» que ahora sale al final.
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_cuando_cobrar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_venta_428_arnes.dart';
import '../../helpers/venta_ui_falsos.dart' show tocar;

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _registrada = Key('venta_registrada_pagina');

void main() {
  late Arnes428 a;
  var cobros = 0;

  setUp(() {
    a = Arnes428();
    cobros = 0;
  });

  /// Hasta 27A·14, con «Cobrar ahora» ofrecido y [alCobrar] como el cobro.
  Future<void> hastaLaRegistrada(
    WidgetTester tester, {
    required Future<bool> Function() alCobrar,
    Size tamano = const Size(390, 1600),
    double letra = 1,
  }) async {
    a.montaje.extra.add(
      cobrarDespuesDeLaVentaProvider.overrideWithValue((contexto) {
        cobros++;
        return alCobrar();
      }),
    );
    await a.montar(tester, tamano: const Size(390, 1600));
    await a.hastaLaVenta(tester);
    await a.armarLaVenta(tester);
    tester.view.physicalSize = tamano;
    a.escala.value = letra;
    await tester.pumpAndSettle();
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await tester.pumpAndSettle();
  }

  group('27A·14 «Venta registrada: ¿y ahora?»', () {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final letra in const [1.0, 2.0]) {
        testWidgets('a ${tamano.width.toInt()}×${tamano.height.toInt()} a $letra×: sin overflow, '
            'botones alcanzables y cumple las guías', (tester) async {
          final semantica = tester.ensureSemantics();
          await hastaLaRegistrada(
            tester,
            alCobrar: () async => false,
            tamano: tamano,
            letra: letra,
          );

          expect(find.byKey(_registrada), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byKey(const Key('venta_terminar')));
          await tester.pump();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }

    testWidgets('dado «atrás» (sistema), entonces no se sale de la pantalla: se sale con «Terminar '
        'sin nada»', (tester) async {
      await hastaLaRegistrada(tester, alCobrar: () async => false);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(_registrada), findsOneWidget);
      expect(a.devolvio, isFalse);
    });

    testWidgets('dado un doble toque en «Terminar sin nada», entonces la pregunta se abre una sola '
        'vez', (tester) async {
      await hastaLaRegistrada(tester, alCobrar: () async => false);

      final terminar = find.byKey(const Key('venta_terminar'));
      await tester.ensureVisible(terminar);
      await tester.tap(terminar);
      await tester.tap(terminar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));
      expect(a.salida, isA<VentaGuardadaEnLaEntrevista>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado «Cobrar ahora» cancelado, entonces pregunta con el saldo entero', (
      tester,
    ) async {
      await hastaLaRegistrada(tester, alCobrar: () async => false);

      await tocar(tester, find.text('Cobrar ahora'));
      await tocar(tester, find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(cobros, 1);
      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      expect(find.textContaining(r'Quedan $ 3.000'), findsOneWidget);
    });

    testWidgets('dado «Cobrar ahora» que lanza, entonces pregunta con el saldo entero y la venta '
        'sigue guardada', (tester) async {
      await hastaLaRegistrada(tester, alCobrar: () async => throw StateError('sin cobro'));

      await tocar(tester, find.text('Cobrar ahora'));
      await tocar(tester, find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.byKey(ClavesCuandoCobrar.hoja), findsOneWidget);
      await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));
      expect(a.entorno.ventas.recibidas, hasLength(1));
      expect(a.salida, isA<VentaGuardadaEnLaEntrevista>());
      expect(tester.takeException(), isNull);
    });
  });

  group('aviso «Venta N guardada.» al final', () {
    // skip: QA #428 — decisión P1: el «Venta N guardada.» sale una sola vez al llegar a R·08, después
    // de la hoja; hoy sale antes y con «Sin fecha» tras >4 s no queda confirmación.
    testWidgets(
      'dado que tardé en elegir y toqué «Sin fecha», entonces el aviso está a la vista',
      (tester) async {
        await hastaLaRegistrada(tester, alCobrar: () async => false);
        await a.tocarKey(tester, const Key('venta_terminar'));

        await tester.pump(const Duration(seconds: 6));
        await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));

        expect(find.text('Venta 0039 guardada.'), findsOneWidget);
      },
      skip: !_verHallazgos,
    );

    testWidgets(
      'dado que agendo «Mañana», entonces el aviso dice la venta y la cita, una sola vez',
      (tester) async {
        await hastaLaRegistrada(tester, alCobrar: () async => false);
        await a.tocarKey(tester, const Key('venta_terminar'));

        await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.manana));
        await a.tocarKey(tester, const Key('agendar_hoja_listo'));

        expect(find.textContaining('Venta 0039 guardada. Cobranza agendada para'), findsOneWidget);
        expect(find.text('Venta 0039 guardada.'), findsNothing);
      },
    );
  });
}
