// Vista 21 (resumen del día) — saludo «Buen trabajo, <nombre>» (#243): con nombre, sin nombre
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

Future<void> _montar(WidgetTester tester, {String? nombre, double escala = 1}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [nombreCuentaProvider.overrideWithValue(nombre)],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: ResumenJornadaPage(jornada: _cerrada()),
      ),
    ),
  );
}

void main() {
  testWidgets('con nombre: «Buen trabajo, Lucía»', (tester) async {
    await _montar(tester, nombre: 'Lucía');

    expect(find.text('Buen trabajo, Lucía'), findsOneWidget);
    expect(find.text('Buen trabajo'), findsNothing);
  });

  testWidgets('sin nombre: «Buen trabajo» a secas, sin coma ni hueco', (tester) async {
    await _montar(tester);

    expect(find.text('Buen trabajo'), findsOneWidget);
    expect(find.textContaining('Buen trabajo,'), findsNothing);
  });

  for (final escala in [1.0, 2.0]) {
    testWidgets('nombre largo a texto x$escala: se parte en renglones, sin desborde', (
      tester,
    ) async {
      await _montar(
        tester,
        nombre: 'María de los Ángeles Fernández de la Vega y Rodríguez-Silva',
        escala: escala,
      );

      expect(
        find.text('Buen trabajo, María de los Ángeles Fernández de la Vega y Rodríguez-Silva'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('jornada_resumen_volver')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('el nombre es lo que el lector de pantalla lee, y no hay otro texto con el nombre', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await _montar(tester, nombre: 'Lucía');

    expect(find.bySemanticsLabel('Buen trabajo, Lucía'), findsOneWidget);
    semantica.dispose();
  });
}
