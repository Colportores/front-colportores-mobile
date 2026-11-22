// HU-NOT-005 / issue #416 — al abrir el centro de notificaciones se revisan los recordatorios que
// sonaron (decisión del 27/10, P1): el aviso que sonó con la app abierta aparece en la lista.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/conciliacion_recordatorios_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';

void main() {
  testWidgets('dado que abro el centro, pide una revisión de los recordatorios que sonaron y el '
      'aviso que llega se ve en la lista', (tester) async {
    final arnes = CentroArnes(avisos: [aviso('viejo', hace: const Duration(days: 1))]);
    var revisiones = 0;
    final conciliador = ConciliadorSerie(() async {
      revisiones++;
      arnes.historial.llegaUno(aviso('nuevo', titulo: 'Recordatorio de visita'));
    });
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...arnes.overrides,
          conciliadorRecordatoriosProvider.overrideWithValue(conciliador),
        ],
        child: MaterialApp(theme: temaClaro(), home: const CentroNotificacionesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(revisiones, 1);
    expect(filaDe('nuevo'), findsOneWidget);
    expect(filaDe('viejo'), findsOneWidget);
  });

  testWidgets('dado que no hay quién revise (sin sesión o sin DB), el centro abre igual', (
    tester,
  ) async {
    final arnes = CentroArnes(avisos: [aviso('viejo')]);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...arnes.overrides, conciliadorRecordatoriosProvider.overrideWithValue(null)],
        child: MaterialApp(theme: temaClaro(), home: const CentroNotificacionesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(filaDe('viejo'), findsOneWidget);
  });
}
