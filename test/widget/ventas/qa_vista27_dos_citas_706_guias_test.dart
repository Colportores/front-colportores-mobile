// QA de «Entrega cita» (27C·02, 27C·03 y la hoja «¿Qué venta?» de la ficha, #706): las guías de
// accesibilidad de Flutter con las dos citas de una venta, a 360×640 y 412×915. Con la letra de prueba
// (Ahem): el contraste con la letra real da falsos negativos.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_entregar_desde_la_ficha.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/marcar_entregado_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar;

final _atrasada = DateTime(2026, 10, 26, 9);
final _sabado = DateTime(2026, 10, 31, 9);
final _martes = DateTime(2026, 11, 3, 16, 30);

EntregaPendiente _deAntes({DateTime? fecha}) => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-1',
  lineas: [lineaDe('e-1', 'p-salud')],
  fechaPrevista: fecha ?? _sabado,
  agendaId: 'a-1',
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

EntregaPendiente _sumado({DateTime? fecha}) => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-1',
  lineas: [lineaDe('e-2', 'p-hijos')],
  fechaPrevista: fecha ?? _martes,
  agendaId: 'a-2',
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

EntregaPendiente get _sinFecha => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-1',
  lineas: [lineaDe('e-3', 'p-salud')],
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

EntornoDeEntrega _entorno(List<EntregaPendiente> lista) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes(lista);
  e.entregas.respuestaDeCumplir = cumplidaCon();
  return e;
}

Future<void> _guias(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

/// La hoja «¿Qué venta?» de la ficha de María con las [lista] de entregas.
Future<EntornoDeEntrega> _montarHoja(
  WidgetTester tester,
  List<EntregaPendiente> lista, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = _entorno(lista)..ahora = ahoraDeLosTests;
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
  return e;
}

void main() {
  group('Guías de accesibilidad con las dos citas de una venta', () {
    for (final t in const [Size(360, 640), Size(412, 915)]) {
      testWidgets('guías de accesibilidad · ${t.width.toInt()}×${t.height.toInt()}', (
        tester,
      ) async {
        final e = _entorno([_deAntes(fecha: _atrasada), _sumado(), _sinFecha]);
        await montarPantalla(
          tester,
          e,
          () => EntregasPendientesPage.ruta(colportorId: 'col-1'),
          tamano: t,
        );

        await _guias(tester);
      });
    }

    testWidgets('guías de accesibilidad de la cita sumada · 360×640', (tester) async {
      final e = _entorno([_deAntes(), _sumado()]);
      await montarPantalla(
        tester,
        e,
        () => MarcarEntregadoPage.rutaDe(CualEntrega.de(_sumado())),
        tamano: const Size(360, 640),
      );

      await _guias(tester);
    });

    for (final t in const [Size(360, 640), Size(412, 915)]) {
      testWidgets('guías de accesibilidad · ${t.width.toInt()}×${t.height.toInt()}', (
        tester,
      ) async {
        await _montarHoja(tester, [_deAntes(), _sumado()], tamano: t);

        await _guias(tester);
      });
    }
  });
}
