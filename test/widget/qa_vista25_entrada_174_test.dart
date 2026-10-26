// QA de la vista 25 (#174, PR #489): la entrada desde Configuración (fila «Sincronización y
// respaldo») y la vuelta atrás. Complementa `qa_vista25_sincronizacion_174_test.dart`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/configuracion_page.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/pages/sincronizacion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sincronizacion_falsos.dart';

void main() {
  testWidgets(
    'dado que estoy en Configuración, cuando toco «Sincronización y respaldo», abre la vista 25 y '
    'volver regresa a Configuración',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = TelefonoSync();
      await tester.pumpWidget(
        ProviderScope(
          overrides: t.overrides,
          child: MaterialApp(theme: temaClaro(), home: const ConfiguracionPage()),
        ),
      );
      await tester.pumpAndSettle();

      final fila = find.byKey(const Key('configuracion_sincronizacion'));
      await tester.scrollUntilVisible(fila, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Sincronización y respaldo'), findsWidgets);
      await tester.tap(fila);
      await tester.pumpAndSettle();
      expect(find.byType(SincronizacionPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('sincronizacion_atras')));
      await tester.pumpAndSettle();
      expect(find.byType(SincronizacionPage), findsNothing);
      expect(find.byType(ConfiguracionPage), findsOneWidget);
    },
  );
}
