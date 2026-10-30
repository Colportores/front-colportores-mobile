// Entrada a la vista 31 (Devolución, HU-VEN-004, #161) desde la ficha de la persona (32B): tocar una
// venta del historial abre su devolución; las demás filas no se tocan; en solo lectura o sin destino
// la venta tampoco.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

void main() {
  MundoFicha mundo({bool conDevolucion = true, bool deBaja = false}) {
    final m = deBaja
        ? MundoFicha(
            persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
            historial: historialDelCanvas(),
            notasIniciales: notasDeLaFicha(),
            contexto: contextoBajaDesde22(),
          )
        : MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha());
    m.conDevolucion = conDevolucion;
    m.cuentas.cuenta = cuentaConSaldo;
    return m;
  }

  final venta = find.text('12/10 · VENTA 0042');
  final visita = find.text('05/10 · VISITA');

  Future<void> traerYTocar(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(f);
      await tester.pump();
    }
    await tester.tap(f);
    await asentar(tester);
  }

  testWidgets(
    'tocar la venta del historial abre su devolución con la venta, la persona y la casa',
    (tester) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: const Size(390, 1600));

      await traerYTocar(tester, venta);

      expect(m.devoluciones, [(ventaId: 'ven-1', personaId: 'per-1', espacioId: 'esp-1')]);
    },
  );

  testWidgets('la fila de la venta se anuncia como botón y tiene la flecha; la visita no', (
    tester,
  ) async {
    final m = mundo();
    await montarFicha(tester, m, tamano: const Size(390, 1600));

    final filas = tester.widgetList<FilaDeHistorial>(find.byType(FilaDeHistorial)).toList();
    expect(filas.where((f) => f.alTocar != null).map((f) => f.movimiento.id), ['ven-1']);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('tocar una visita no abre ninguna devolución', (tester) async {
    final m = mundo();
    await montarFicha(tester, m, tamano: const Size(390, 1600));

    await traerYTocar(tester, visita);

    expect(m.devoluciones, isEmpty);
  });

  testWidgets('un doble toque mientras se abre la devolución la abre una sola vez', (tester) async {
    final m = mundo()..compuertaDevolucion = Completer<void>();
    await montarFicha(tester, m, tamano: const Size(390, 1600));
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(venta);
      await tester.pump();
    }

    await tester.tap(venta);
    await tester.tap(venta);
    await tester.pump();

    expect(m.devoluciones, hasLength(1));

    m.compuertaDevolucion!.complete();
    await asentar(tester);
    // Ya volvió: se puede abrir otra vez (volver y reentrar).
    await tester.tap(venta);
    await asentar(tester);
    expect(m.devoluciones, hasLength(2));
  });

  testWidgets('sin destino de devolución la venta no se toca ni lleva flecha', (tester) async {
    final m = mundo(conDevolucion: false);
    await montarFicha(tester, m, tamano: const Size(390, 1600));

    await traerYTocar(tester, venta);

    expect(m.devoluciones, isEmpty);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('con la persona de baja (solo lectura) la venta no se toca', (tester) async {
    final m = mundo(deBaja: true);
    await montarFicha(tester, m, tamano: const Size(390, 1600));

    await traerYTocar(tester, venta);

    expect(m.devoluciones, isEmpty);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('con letra al doble la fila de la venta con flecha no desborda', (tester) async {
    final m = mundo();
    await montarFicha(tester, m, escala: 2, tamano: const Size(320, 1800));

    await tester.scrollUntilVisible(venta, 300, scrollable: find.byType(Scrollable).first);
    expect(venta, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
