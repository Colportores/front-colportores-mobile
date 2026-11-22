// «Entrega cita» (decisión de Cristian del 11/11, #706): una venta que creció puede tener dos citas de
// entrega, una por grupo de libros. «Marcar entregado», «Entregas pendientes», la hoja «¿Qué venta?»
// de la ficha, «Poner fecha» y «Entregado hoy» de la Agenda trabajan con los libros de UNA cita.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_entregar_desde_la_ficha.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregar_otro_dia_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/marcar_entregado_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

Finder get _cta => find.byKey(const Key('venta_cta'));

final _sabado = DateTime(2026, 10, 31, 9);
final _martes = DateTime(2026, 11, 3, 16, 30);

/// Lo de antes de la venta 0042: «Salud y Hogar», con su cita del sábado.
EntregaPendiente get _deAntes => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-p1',
  lineas: [lineaDe('e-1', 'p-salud')],
  fechaPrevista: _sabado,
  agendaId: 'a-1',
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

/// El libro que se le sumó: «Nuestros Hijos», con su propia cita del martes.
EntregaPendiente get _sumado => EntregaPendiente(
  ventaId: 'v-1',
  espacioPersonaId: 'ep-p1',
  lineas: [lineaDe('e-2', 'p-hijos')],
  fechaPrevista: _martes,
  agendaId: 'a-2',
  espacioId: 'esp-1',
  numeroTalonario: '0042',
);

/// Abre la hoja «Día y hora», elige mañana y toca «Listo».
Future<void> _elegirManana(WidgetTester tester) async {
  await tocar(tester, find.byKey(const Key('entrega_campo_fecha')));
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.dia(1)));
  await tester.tap(find.byKey(ClavesAgendarVisita.dia(1)));
  await tester.pump();
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.hojaListo));
  await tester.tap(find.byKey(ClavesAgendarVisita.hojaListo));
  await asentar(tester);
}

EntornoDeEntrega _entorno(List<EntregaPendiente> lista) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes(lista);
  e.entregas.respuestaDeCumplir = cumplidaCon();
  return e;
}

void main() {
  group('CualEntrega: cuál de las entregas de la venta', () {
    final sinFecha = EntregaPendiente(
      ventaId: 'v-1',
      espacioPersonaId: 'ep-p1',
      lineas: [lineaDe('e-3', 'p-salud')],
    );
    final lista = [_deAntes, _sumado, sinFecha];

    test('por la cita, aunque la fecha haya cambiado', () {
      expect(CualEntrega('v-1', agendaId: 'a-2', fechaPrevista: _sabado).en(lista), _sumado);
    });

    test('por la fecha, sin cita', () {
      expect(CualEntrega('v-1', fechaPrevista: _martes).en(lista), _sumado);
      expect(CualEntrega('v-1', fechaPrevista: DateTime(2027)).en(lista), isNull);
    });

    test('la sin fecha, aunque la venta tenga otras con fecha', () {
      expect(CualEntrega.de(sinFecha).en(lista), sinFecha);
    });

    test('sin decir cuál, la primera de la venta; de otra venta, ninguna', () {
      expect(const CualEntrega('v-1').en(lista), _deAntes);
      expect(const CualEntrega('v-9').en(lista), isNull);
    });

    test('una cita que ya no está no cae en otra de la venta', () {
      expect(const CualEntrega('v-1', agendaId: 'a-9').en(lista), isNull);
    });
  });

  group('«Marcar entregado» de una de las dos citas', () {
    testWidgets('muestra y entrega solo los libros de esa cita', (tester) async {
      final e = _entorno([_deAntes, _sumado]);
      final salida = await montarPantalla(
        tester,
        e,
        () => MarcarEntregadoPage.rutaDe(CualEntrega.de(_sumado)),
      );

      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsNothing);

      await tocar(tester, _cta);

      expect(e.entregas.cumplidas.single.entregaIds, {'e-2'});
      expect(salida.cerrada, isTrue);
    });

    testWidgets('doble toque: una sola llamada', (tester) async {
      final e = _entorno([_deAntes, _sumado]);
      await montarPantalla(tester, e, () => MarcarEntregadoPage.rutaDe(CualEntrega.de(_deAntes)));

      await tester.tap(_cta);
      await tester.tap(_cta, warnIfMissed: false);
      await asentar(tester);

      expect(e.entregas.cumplidas, hasLength(1));
      expect(e.entregas.cumplidas.single.entregaIds, {'e-1'});
    });
  });

  group('«Entregas pendientes» con las dos citas de la venta', () {
    // Decisión del 12/11, P2 del QA de #709: «Venta 0042» solo si la venta tiene más de una tarjeta.
    testWidgets('las dos tarjetas de la misma venta dicen «Venta 0042»', (tester) async {
      final e = _entorno([_deAntes, _sumado]);
      await montarPantalla(tester, e, () => EntregasPendientesPage.ruta(colportorId: 'col-1'));

      expect(find.textContaining('Venta 0042'), findsNWidgets(2));
    });

    testWidgets('con una sola tarjeta de la venta, como el canvas: sin el número', (tester) async {
      final e = _entorno([_deAntes]);
      await montarPantalla(tester, e, () => EntregasPendientesPage.ruta(colportorId: 'col-1'));

      expect(find.textContaining('Salud y Hogar'), findsOneWidget);
      expect(find.textContaining('Venta 0042'), findsNothing);
    });

    test('el detalle con la venta va primero y sin la venta queda como estaba', () {
      const nombres = {'p-hijos': 'Nuestros Hijos'};
      expect(
        FormatoEntregaDiferida.detalleDeLaTarjeta(
          _sumado,
          direccion: 'Grecia 3310',
          nombres: nombres,
          conVenta: true,
        ),
        'Venta 0042 · Grecia 3310 · Nuestros Hijos × 1',
      );
      expect(
        FormatoEntregaDiferida.detalleDeLaTarjeta(
          _sumado,
          direccion: 'Grecia 3310',
          nombres: nombres,
        ),
        'Grecia 3310 · Nuestros Hijos × 1',
      );
    });

    testWidgets('una tarjeta por cita; tocar la del martes abre solo su libro', (tester) async {
      final e = _entorno([_deAntes, _sumado]);
      await montarPantalla(tester, e, () => EntregasPendientesPage.ruta(colportorId: 'col-1'));

      expect(find.textContaining('Salud y Hogar'), findsOneWidget);
      expect(find.textContaining('Nuestros Hijos'), findsOneWidget);

      await tocar(tester, find.textContaining('Nuestros Hijos'));

      expect(find.byKey(const Key('marcar_pagina')), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsNothing);
    });

    testWidgets('«Poner fecha» de lo que quedó sin fecha manda solo esas filas', (tester) async {
      final sinFecha = EntregaPendiente(
        ventaId: 'v-1',
        espacioPersonaId: 'ep-p1',
        lineas: [lineaDe('e-3', 'p-salud')],
        espacioId: 'esp-1',
        numeroTalonario: '0042',
      );
      final e = _entorno([_sumado, sinFecha]);
      await montarPantalla(
        tester,
        e,
        () => EntregarOtroDiaPage.rutaPonerFecha(colportorId: 'col-1', pendiente: sinFecha),
      );
      await _elegirManana(tester);
      await tocar(tester, _cta);

      expect(e.entregas.entregaIdsAlDiferir.single, {'e-3'});
    });
  });

  group('la hoja «¿Qué venta?» de la ficha con las dos citas de una venta', () {
    Future<EntornoDeEntrega> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final e = _entorno([_deAntes, _sumado])..ahora = ahoraDeLosTests;
      final personas = PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'María')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overridesDeEntregaDiferida(e),
            personaRepositoryProvider.overrideWithValue(personas),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: const Key('abrir'),
                    onPressed: () => FlujoEntregarDesdeLaFicha.abrir(
                      context,
                      personaId: 'p1',
                      espacioId: 'esp-1',
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
      return e;
    }

    testWidgets('pregunta cuál y abre la elegida', (tester) async {
      await montar(tester);

      expect(tester.takeException(), isNull, reason: 'las dos de la misma venta no repiten clave');
      expect(find.byKey(const ValueKey('que_entrega_v-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('que_entrega_v-1_1')), findsOneWidget);

      await tocar(tester, find.byKey(const ValueKey('que_entrega_v-1_1')));

      expect(find.byKey(const Key('marcar_pagina')), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsNothing);
    });
  });

  group('«Entregar» de la tarjeta de la ficha con su fecha', () {
    testWidgets('abre la entrega de esa fecha, no la primera de la venta', (tester) async {
      final e = _entorno([_deAntes, _sumado]);
      await montarPantalla(tester, e, () {
        return MaterialPageRoute<bool>(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('entregar_fila'),
                onPressed: () => FlujoEntregarDesdeLaFicha.abrir(
                  context,
                  personaId: 'p1',
                  espacioId: 'esp-1',
                  ventaId: 'v-1',
                  fechaPrevista: _martes,
                ),
                child: const Text('Entregar'),
              ),
            ),
          ),
        );
      });

      await tocar(tester, find.byKey(const Key('entregar_fila')));

      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsNothing);
    });
  });
}
