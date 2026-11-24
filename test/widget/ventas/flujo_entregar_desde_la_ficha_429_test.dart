// «Registrar entrega» y «Entregar» de la ficha de la persona (vista 32, 32B·01, #429) hasta «Marcar
// entregado» (27C·03, #435): lo que enchufa `registrarEntregaDesdeLaFichaProvider` (decisiones del
// 30/10 por #602 y del 10/11 por el QA de #678). Con la venta de la fila abre directo; desde el chip,
// «¿Qué venta?» solo si hay más de una con algo pendiente.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_entregar_desde_la_ficha.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/marcar_entregado_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

/// Lo que devolvió el flujo, y cuántas veces terminó.
final class _Salida {
  final valores = <bool>[];
}

EntregaPendiente _de(String venta, String talonario, {DateTime? fecha}) => pendienteDe(
  venta,
  vinculo: 'ep-p1',
  talonario: talonario,
  fecha: fecha,
  lineas: [lineaDe('e-$venta', 'p-salud')],
);

Future<_Salida> _montar(
  WidgetTester tester, {
  required List<EntregaPendiente> pendientes,
  String? ventaId,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = EntornoDeEntrega()..ahora = ahoraDeLosTests;
  e.entregas.emitirPendientes(pendientes);
  e.entregas.respuestaDeCumplir = cumplidaCon();
  final personas = PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'María')]);
  final salida = _Salida();
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
                onPressed: () async => salida.valores.add(
                  await FlujoEntregarDesdeLaFicha.abrir(
                    context,
                    personaId: 'p1',
                    espacioId: 'esp-1',
                    ventaId: ventaId,
                  ),
                ),
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
  return salida;
}

void main() {
  testWidgets('«Entregar» en la fila abre «Marcar entregado» de esa venta, sin preguntar', (
    tester,
  ) async {
    await _montar(tester, pendientes: [_de('v-1', '0042'), _de('v-2', '0043')], ventaId: 'v-2');

    expect(find.byType(MarcarEntregadoPage), findsOneWidget);
    expect(tester.widget<MarcarEntregadoPage>(find.byType(MarcarEntregadoPage)).ventaId, 'v-2');
    expect(find.text(TextosEntregaDiferida.queVenta), findsNothing);
  });

  testWidgets('el chip con una sola venta pendiente abre «Marcar entregado» directo', (
    tester,
  ) async {
    await _montar(tester, pendientes: [_de('v-1', '0042')]);

    expect(find.text(TextosEntregaDiferida.queVenta), findsNothing);
    expect(tester.widget<MarcarEntregadoPage>(find.byType(MarcarEntregadoPage)).ventaId, 'v-1');
  });

  testWidgets(
    'el chip con dos ventas pregunta «¿Qué venta?» y abre la elegida; marcar la devuelve',
    (tester) async {
      final salida = await _montar(
        tester,
        pendientes: [
          _de('v-1', '0042', fecha: DateTime(2026, 10, 31, 16, 30)),
          _de('v-2', '0043'),
        ],
      );

      expect(find.text(TextosEntregaDiferida.queVenta), findsOneWidget);
      expect(find.text('Venta 0042'), findsOneWidget);
      expect(find.text('Venta 0043'), findsOneWidget);

      await tocar(tester, find.byKey(const ValueKey('que_entrega_v-2')));

      expect(find.text(TextosEntregaDiferida.queVenta), findsNothing);
      expect(tester.widget<MarcarEntregadoPage>(find.byType(MarcarEntregadoPage)).ventaId, 'v-2');

      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.byType(MarcarEntregadoPage), findsNothing);
      expect(salida.valores, [true]);
    },
  );

  testWidgets('«Cancelar» en «¿Qué venta?» no abre nada y se puede volver a empezar', (
    tester,
  ) async {
    final salida = await _montar(tester, pendientes: [_de('v-1', '0042'), _de('v-2', '0043')]);

    await tocar(tester, find.byKey(const Key('que_entrega_cancelar')));

    expect(find.byType(MarcarEntregadoPage), findsNothing);
    expect(salida.valores, [false]);

    await tester.tap(find.byKey(const Key('abrir')));
    await asentar(tester);
    expect(find.text(TextosEntregaDiferida.queVenta), findsOneWidget);
  });

  testWidgets('dos toques seguidos en una fila de «¿Qué venta?» abren una sola pantalla', (
    tester,
  ) async {
    await _montar(tester, pendientes: [_de('v-1', '0042'), _de('v-2', '0043')]);

    final fila = find.byKey(const ValueKey('que_entrega_v-1'));
    await tester.tap(fila);
    await tester.tap(fila, warnIfMissed: false);
    await asentar(tester);

    expect(find.byType(MarcarEntregadoPage), findsOneWidget);
  });

  testWidgets('sin nada pendiente (se entregó con la ficha abierta) lo dice y no abre nada', (
    tester,
  ) async {
    final salida = await _montar(tester, pendientes: const []);

    expect(find.byType(MarcarEntregadoPage), findsNothing);
    expect(find.text(TextosEntregaDiferida.sinPendientesDeLaPersona), findsOneWidget);
    expect(salida.valores, [false]);
  });

  testWidgets('«¿Qué venta?» con muchas ventas y texto al 200 % se recorre entera', (tester) async {
    await _montar(
      tester,
      escala: 2,
      pendientes: [for (var i = 0; i < 12; i++) _de('v-$i', '00${40 + i}')],
    );

    final ultima = find.byKey(const ValueKey('que_entrega_v-11'));
    await tester.scrollUntilVisible(ultima, 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(ultima);
    await asentar(tester);

    expect(tester.widget<MarcarEntregadoPage>(find.byType(MarcarEntregadoPage)).ventaId, 'v-11');
    expect(tester.takeException(), isNull);
  });
}
