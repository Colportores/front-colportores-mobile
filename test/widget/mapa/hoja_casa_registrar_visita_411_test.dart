// Vista 39, #411: lo que la hoja de la casa (C·01) hace con lo que contesta «Registrar visita»: si se
// resolvió (`true`) la hoja se cierra; con cualquier otra cosa sigue abierta. Una sola acción a la vez.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;

Future<List<int>> _montar(
  WidgetTester tester, {
  required FutureOr<Object?> Function() alRegistrar,
}) async {
  final cierres = <int>[];
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overridesHojaCasa(registrarVisita: (_) => alRegistrar()),
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

Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);

void main() {
  testWidgets('dado que se guardó (el destino contesta true), cuando vuelve, la hoja se cierra una '
      'sola vez', (tester) async {
    final cierres = await _montar(tester, alRegistrar: () async => true);

    await tester.tap(_registrar);
    await tester.pump();
    await tester.pump();

    expect(cierres, hasLength(1));
  });

  testWidgets('dado que se cerró «¿Qué pasó?» sin elegir (false), cuando vuelve, la hoja sigue '
      'abierta y se puede volver a tocar', (tester) async {
    final cierres = await _montar(tester, alRegistrar: () async => false);

    await tester.tap(_registrar);
    await tester.pump();
    await tester.pump();
    await tester.tap(_registrar);
    await tester.pump();
    await tester.pump();

    expect(cierres, isEmpty);
    expect(_registrar, findsOneWidget);
  });

  testWidgets('dado un destino que no contesta nada (null), cuando vuelve, la hoja sigue abierta', (
    tester,
  ) async {
    final cierres = await _montar(tester, alRegistrar: () => null);

    await tester.tap(_registrar);
    await tester.pump();
    await tester.pump();

    expect(cierres, isEmpty);
  });

  testWidgets(
    'dado un doble toque mientras «¿Qué pasó?» está abierta, cuando termina, se abrió una '
    'sola vez y la hoja se cierra una sola vez',
    (tester) async {
      final compuerta = Completer<bool>();
      var aperturas = 0;
      final cierres = await _montar(
        tester,
        alRegistrar: () {
          aperturas++;
          return compuerta.future;
        },
      );

      await tester.tap(_registrar);
      await tester.tap(_registrar, warnIfMissed: false);
      await tester.pump();
      compuerta.complete(true);
      await tester.pump();
      await tester.pump();

      expect(aperturas, 1);
      expect(cierres, hasLength(1));
    },
  );

  testWidgets('dado un destino que falla, cuando se toca, la hoja avisa, sigue abierta y el botón '
      'vuelve a poder tocarse', (tester) async {
    var llamadas = 0;
    final cierres = await _montar(
      tester,
      alRegistrar: () {
        llamadas++;
        if (llamadas == 1) throw StateError('no abrió');
        return true;
      },
    );

    await tester.tap(_registrar);
    await tester.pump();
    await tester.pump();
    expect(cierres, isEmpty);
    expect(find.textContaining('No pudimos'), findsWidgets);

    await tester.tap(_registrar);
    await tester.pump();
    await tester.pump();

    expect(llamadas, 2);
    expect(cierres, hasLength(1));
  });
}
