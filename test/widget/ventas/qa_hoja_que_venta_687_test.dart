// QA de la hoja «¿Qué venta?» del chip «Registrar entrega» de la ficha (#429, PR #687): la hoja no
// tiene artboard, así que se prueba con las guías de Flutter, la letra al 200 % y las listas largas en
// los dos tamaños del QA. Capturas solo con `--dart-define=QA_CAPTURAS=true`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_entregar_desde_la_ficha.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_entrega_diferida.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista27_entrega_435_arnes.dart'
    show capturar435, cargarFuentes408, conCapturas408;
import '../../helpers/venta_ui_falsos.dart' show asentar;

EntregaPendiente _de(int n) => pendienteDe(
  'v-$n',
  vinculo: 'ep-p1',
  talonario: (1000 + n).toString(),
  fecha: n.isEven ? null : DateTime(2026, 10, 31, 9),
  lineas: [lineaDe('e-$n', 'p-salud')],
);

Future<void> _montar(
  WidgetTester tester, {
  required int ventas,
  Size? tamano,
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano ?? const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntornoDeEntrega()..ahora = ahoraDeLosTests;
  e.entregas.emitirPendientes([for (var i = 1; i <= ventas; i++) _de(i)]);
  final personas = PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'María')]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesDeEntregaDiferida(e),
        personaRepositoryProvider.overrideWithValue(personas),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir'),
                onPressed: () =>
                    FlujoEntregarDesdeLaFicha.abrir(context, personaId: 'p1', espacioId: 'esp-1'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await asentar(tester);
}

void main() {
  group('hoja «¿Qué venta?»', () {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        for (final ventas in const [2, 40]) {
          final rotulo =
              '$ventas ventas · ${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x';

          testWidgets('sin overflow y con las guías de Flutter · $rotulo', (tester) async {
            final handle = tester.ensureSemantics();
            await _montar(tester, ventas: ventas, tamano: tamano, escala: escala);

            expect(find.text(TextosEntregaDiferida.queVenta), findsOneWidget);
            expect(find.text('Cancelar'), findsOneWidget, reason: 'siempre hay una salida a mano');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            expect(tester.takeException(), isNull);
            handle.dispose();
          });
        }
      }
    }

    for (final escala in const [1.0, 2.0]) {
      testWidgets('capturas · ${escala}x', (tester) async {
        if (!conCapturas408) return;
        await cargarFuentes408(tester);
        await _montar(tester, ventas: 3, escala: escala);
        await capturar435(tester, '687_queVenta_360_${escala.toInt()}x');
      });
    }
  });
}
