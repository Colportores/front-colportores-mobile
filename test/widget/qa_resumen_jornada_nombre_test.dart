// QA #243 — Vista 21 (resumen del día) — saludo «Buen trabajo, <nombre>» (#243): con nombre, sin nombre
// (cuenta sin nombre), nombre largo y texto grande.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/nombre_cuenta_provider.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/presentation/pages/resumen_jornada_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _inicio = DateTime.utc(2026, 9, 30, 13, 15);

Jornada _cerrada() => Jornada(
  id: 'jor-1',
  colportorId: 'u-1',
  inicio: _inicio,
  fin: _inicio.add(const Duration(hours: 1, minutes: 20)),
  auditoria: Auditoria(createdAt: _inicio, updatedAt: _inicio, createdBy: 'u-1'),
);

Future<void> _montar(WidgetTester tester, {String? nombre}) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [nombreCuentaProvider.overrideWithValue(nombre)],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ResumenJornadaPage(jornada: _cerrada()),
      ),
    ),
  );
}

void main() {
  for (final nombre in [
    'Maximiliano-Bartolomé-Fernández-de-Córdoba-y-Rodríguez-Silva',
    'Ñandú Ünal Ångström',
    '李小龍 😀',
  ]) {
    testWidgets('a 360x640 con texto 2.0, el saludo con «$nombre» no desborda ni tapa el botón', (
      tester,
    ) async {
      await _montar(tester, nombre: nombre);

      expect(tester.takeException(), isNull);
      expect(find.text('Buen trabajo, $nombre'), findsOneWidget);
      final saludo = tester.getRect(find.byKey(const Key('jornada_resumen_saludo')));
      expect(saludo.right, lessThanOrEqualTo(360));
      final volver = find.byKey(const Key('jornada_resumen_volver'));
      await tester.ensureVisible(volver);
      await tester.pumpAndSettle();
      expect(volver, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
