// La campana del encabezado de Hoy (vista 00 / 24, HU-NOT-005, #156): el número de avisos sin leer,
// cómo la lee el lector de pantalla y que abre el centro una sola vez.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/campana_notificaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';

final _campana = find.byKey(const Key('inicio_notificaciones'));
final _numero = find.byKey(const Key('inicio_notificaciones_numero'));

Future<void> _montar(
  WidgetTester tester,
  CentroArnes arnes, {
  bool conBase = true,
  double texto = 1,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: conBase ? arnes.overrides : const [],
      child: MaterialApp(
        theme: temaClaro(),
        home: Scaffold(
          appBar: AppBar(title: const Text('Hoy'), actions: const [CampanaNotificaciones()]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin avisos sin leer la campana está sola, sin número', (tester) async {
    await _montar(tester, CentroArnes(avisos: [aviso('a', leida: true)]));

    expect(_campana, findsOneWidget);
    expect(_numero, findsNothing);
    expect(tester.widget<IconButton>(_campana).tooltip, 'Notificaciones');
  });

  testWidgets('con avisos sin leer muestra cuántos, y el lector de pantalla lo dice una vez', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await _montar(tester, CentroArnes(avisos: [aviso('a'), aviso('b'), aviso('c', leida: true)]));

    expect(tester.widget<Text>(_numero).data, '2');
    // El IconButton publica su `tooltip` como el nombre del botón para el lector de pantalla.
    expect(tester.getSemantics(_campana).tooltip, 'Notificaciones, 2 sin leer');
    expect(find.bySemanticsLabel('2'), findsNothing, reason: 'el globo no se lee aparte');
    semantica.dispose();
  });

  testWidgets('con una sola sin leer, la etiqueta va en singular', (tester) async {
    await _montar(tester, CentroArnes(avisos: [aviso('a')]));

    expect(tester.widget<IconButton>(_campana).tooltip, 'Notificaciones, 1 sin leer');
  });

  testWidgets('más de 99 se escribe «99+»', (tester) async {
    final avisos = [for (var i = 0; i < 120; i++) aviso('n-$i', hace: Duration(minutes: i + 1))];
    await _montar(tester, CentroArnes(avisos: avisos));

    expect(find.text('99+'), findsOneWidget);
    expect(tester.widget<IconButton>(_campana).tooltip, 'Notificaciones, 120 sin leer');
  });

  testWidgets('el número sube cuando llega un aviso y baja cuando se leen', (tester) async {
    final arnes = CentroArnes(avisos: [aviso('a')]);
    await _montar(tester, arnes);
    expect(find.text('1'), findsOneWidget);

    arnes.historial.llegaUno(aviso('b', hace: Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await arnes.historial.marcarTodasLeidas(ahora: ahoraDelCentro);
    await tester.pumpAndSettle();
    expect(_numero, findsNothing);
  });

  testWidgets('tocarla abre el centro; un doble toque lo abre una sola vez', (tester) async {
    final arnes = CentroArnes(avisos: [aviso('a')]);
    arnes.historial.puertaAlObservar = Completer<void>();
    await _montar(tester, arnes);

    await tester.tap(_campana);
    await tester.tap(_campana, warnIfMissed: false);
    await tester.pump();
    arnes.historial.puertaAlObservar!.complete();
    await tester.pumpAndSettle();

    expect(centroPagina, findsOneWidget);
    await tester.tap(find.byKey(const Key('centro_atras')));
    await tester.pumpAndSettle();
    expect(centroPagina, findsNothing, reason: 'una sola pantalla apilada');
    expect(find.text('Hoy'), findsOneWidget);
  });

  testWidgets('sin la base abierta la campana no muestra error ni número', (tester) async {
    await _montar(tester, CentroArnes(), conBase: false);

    expect(tester.takeException(), isNull);
    expect(_campana, findsOneWidget);
    expect(_numero, findsNothing);
  });

  testWidgets('con el texto al 200 % y un número de dos cifras no desborda', (tester) async {
    final avisos = [for (var i = 0; i < 42; i++) aviso('n-$i', hace: Duration(minutes: i + 1))];
    await _montar(tester, CentroArnes(avisos: avisos), texto: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('42'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
