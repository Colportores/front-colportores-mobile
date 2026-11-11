// Vista 39, #440: lo que la hoja de la casa (C·01) hace con lo que contesta «$ Cobrar»: si se cobró
// (`true`) o quedó anotada la visita «Cobranza» sin cobro (`CobranzaAnotadaSinCobro`, decisión de
// Cristian del 03/11) la hoja se cierra y el mapa queda libre; con cualquier otra cosa sigue abierta.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;

Future<List<int>> _montar(
  WidgetTester tester, {
  required FutureOr<Object?> Function() alCobrar,
}) async {
  final cierres = <int>[];
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overridesHojaCasa(cobrar: (_) => alCobrar()),
      child: MaterialApp(
        theme: temaClaro(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () => cierres.add(cierres.length),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return cierres;
}

Finder get _cobrar => find.text(r'$ Cobrar');

Future<void> _tocarCobrar(WidgetTester tester) async {
  await tester.tap(_cobrar);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('dado que se cobró (true), la hoja se cierra una sola vez', (tester) async {
    final cierres = await _montar(tester, alCobrar: () async => true);

    await _tocarCobrar(tester);

    expect(cierres, hasLength(1));
  });

  testWidgets('dado que se anotó la visita sin cobro (03/11), la hoja se cierra una sola vez y el '
      'mapa queda libre', (tester) async {
    final cierres = await _montar(tester, alCobrar: () async => const CobranzaAnotadaSinCobro());

    await _tocarCobrar(tester);

    expect(cierres, hasLength(1));
  });

  testWidgets('dado «No, me equivoqué» (false), la hoja sigue abierta y se puede volver a tocar', (
    tester,
  ) async {
    final cierres = await _montar(tester, alCobrar: () async => false);

    await _tocarCobrar(tester);
    await _tocarCobrar(tester);

    expect(cierres, isEmpty);
    expect(_cobrar, findsOneWidget);
  });

  testWidgets('dado un doble toque mientras el flujo está abierto, el flujo se abre una sola vez '
      'y la hoja se cierra una sola vez', (tester) async {
    final compuerta = Completer<Object?>();
    var aperturas = 0;
    final cierres = await _montar(
      tester,
      alCobrar: () {
        aperturas++;
        return compuerta.future;
      },
    );

    await tester.tap(_cobrar);
    await tester.tap(_cobrar, warnIfMissed: false);
    await tester.pump();
    compuerta.complete(const CobranzaAnotadaSinCobro());
    await tester.pump();
    await tester.pump();

    expect(aperturas, 1);
    expect(cierres, hasLength(1));
  });
}
