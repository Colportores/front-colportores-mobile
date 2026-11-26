// «Nombre ubic.» (Cristian, 24/11; #769, backend-supabase 0206): el nombre opcional del lugar va donde hoy va
// la dirección de la ubicación alternativa (vista 22A: «Farmacia Italia» arriba, «Av. Italia 2810 · Negocio»
// debajo). Sin nombre todo queda como estaba: la dirección arriba y el tipo debajo.
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ubicacion_alternativa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

void main() {
  final farmacia = ubicacionParaAlternativa('ub-2', nombre: 'Farmacia Italia');
  final sinNombre = ubicacionParaAlternativa('ub-3', calle: 'Mataojo', numero: '2051');
  final deBaja = ubicacionParaAlternativa(
    'ub-2',
    nombre: 'Farmacia Italia',
    deletedAt: DateTime(2026, 10, 20),
  );

  const alto = Size(390, 1700);

  MundoFicha mundo({
    EstadoUbicacionAlternativa estado = const SinUbicacionAlternativa(),
    List<Ubicacion>? candidatas,
  }) {
    final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha());
    m.alternativas
      ..ponerEstado(estado)
      ..ponerCandidatas(candidatas ?? [farmacia, sinNombre]);
    return m;
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await asentar(tester);
  }

  final vigente = find.byKey(ClavesAlternativa.vigente);
  final quitar = find.byKey(ClavesAlternativa.quitar);
  final sin = find.byKey(ClavesAlternativa.sinAlternativa);

  group('22A·02 · el selector', () {
    testWidgets('la fila con nombre dice el nombre arriba y la dirección con el tipo debajo', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: alto);

      await tocar(tester, sin);

      final fila = find.byKey(ClavesAlternativa.fila('ub-2'));
      expect(find.descendant(of: fila, matching: find.text('Farmacia Italia')), findsOneWidget);
      expect(
        find.descendant(of: fila, matching: find.text('Av. Italia 2810 · Negocio')),
        findsOneWidget,
      );
      expect(find.descendant(of: fila, matching: find.text('Av. Italia 2810')), findsNothing);
    });

    testWidgets('la fila sin nombre queda como estaba: la dirección arriba y el tipo debajo', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: alto);

      await tocar(tester, sin);

      final fila = find.byKey(ClavesAlternativa.fila('ub-3'));
      expect(find.descendant(of: fila, matching: find.text('Mataojo 2051')), findsOneWidget);
      expect(find.descendant(of: fila, matching: find.text('Negocio')), findsOneWidget);
    });

    testWidgets('el lector de pantalla anuncia el nombre, la dirección y el tipo', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo(), tamano: alto);
      await tocar(tester, sin);

      final nodo = tester.getSemantics(find.byKey(ClavesAlternativa.fila('ub-2')));

      expect(nodo.label, 'Farmacia Italia, Av. Italia 2810 · Negocio');
      semantica.dispose();
    });

    testWidgets('buscar por el nombre la encuentra («Buscar por dirección o nombre»)', (
      tester,
    ) async {
      await montarFicha(tester, mundo(), tamano: alto);
      await tocar(tester, sin);

      await tester.enterText(find.byKey(ClavesAlternativa.selectorBuscar), 'farmacia');
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsNothing);
    });

    testWidgets('buscar sin acentos ni mayúsculas igual la encuentra, y por la dirección también', (
      tester,
    ) async {
      final acentos = ubicacionParaAlternativa(
        'ub-4',
        nombre: 'Panadería Ñandú',
        calle: 'Rivera',
        numero: '10',
      );
      await montarFicha(tester, mundo(candidatas: [farmacia, acentos]), tamano: alto);
      await tocar(tester, sin);

      await tester.enterText(find.byKey(ClavesAlternativa.selectorBuscar), 'PANADERIA nandu');
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.fila('ub-4')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsNothing);

      await tester.enterText(find.byKey(ClavesAlternativa.selectorBuscar), 'italia');
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
    });

    testWidgets('un nombre de 80 caracteres con el texto al 200 % entra sin desbordar', (
      tester,
    ) async {
      final larga = ubicacionParaAlternativa(
        'ub-5',
        nombre: ('Farmacia Italia ' * 6).substring(0, 80),
      );
      await montarFicha(
        tester,
        mundo(candidatas: [larga]),
        escala: 2,
        tamano: const Size(360, 3200),
      );
      await tocar(tester, sin);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesAlternativa.fila('ub-5')), findsOneWidget);
    });
  });

  group('22A·06 y 22A·07 · la ficha con la alternativa vigente', () {
    testWidgets('elegir la ubicación con nombre avisa con el nombre y deja «SE COBRA ACÁ» con él', (
      tester,
    ) async {
      final m = mundo();
      await montarFicha(tester, m, tamano: alto);

      await tocar(tester, sin);
      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
      await asentar(tester);

      expect(m.alternativas.establecidas, ['ub-2']);
      expect(
        find.text('Las cobranzas de María se van a proponer en Farmacia Italia.'),
        findsOneWidget,
      );
      expect(find.descendant(of: vigente, matching: find.text('Farmacia Italia')), findsOneWidget);
      expect(
        find.descendant(of: vigente, matching: find.text('Av. Italia 2810 · Negocio')),
        findsOneWidget,
      );
    });

    testWidgets('la vigente sin nombre sigue mostrando la dirección y el tipo', (tester) async {
      await montarFicha(
        tester,
        mundo(estado: UbicacionAlternativaVigente(sinNombre)),
        tamano: alto,
      );

      expect(find.descendant(of: vigente, matching: find.text('Mataojo 2051')), findsOneWidget);
      expect(find.descendant(of: vigente, matching: find.text('Negocio')), findsOneWidget);
    });

    testWidgets('«Quitar» pregunta por el nombre: «¿Quitar Farmacia Italia?»', (tester) async {
      await montarFicha(tester, mundo(estado: UbicacionAlternativaVigente(farmacia)), tamano: alto);

      await tocar(tester, quitar);

      expect(find.byKey(ClavesAlternativa.hojaQuitar), findsOneWidget);
      expect(find.text('¿Quitar Farmacia Italia?'), findsOneWidget);
    });

    testWidgets('«Quitar» dice cuál ubicación quita con el nombre para el lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo(estado: UbicacionAlternativaVigente(farmacia)), tamano: alto);

      expect(tester.getSemantics(quitar).label, 'Quitar la ubicación alternativa Farmacia Italia');
      semantica.dispose();
    });

    testWidgets('dada de baja: la tarjeta tachada lleva el nombre y la dirección debajo', (
      tester,
    ) async {
      await montarFicha(
        tester,
        mundo(estado: UbicacionAlternativaDeBaja('ub-2', ubicacion: deBaja)),
        tamano: alto,
      );

      final tarjeta = find.byKey(ClavesAlternativa.deBaja);
      expect(find.descendant(of: tarjeta, matching: find.text('Farmacia Italia')), findsOneWidget);
      expect(
        find.descendant(of: tarjeta, matching: find.text('Av. Italia 2810 · Negocio')),
        findsOneWidget,
      );
    });

    testWidgets('con el texto al 200 % la tarjeta vigente con nombre entra sin desbordar', (
      tester,
    ) async {
      await montarFicha(
        tester,
        mundo(estado: UbicacionAlternativaVigente(farmacia)),
        escala: 2,
        tamano: const Size(360, 3200),
      );

      expect(tester.takeException(), isNull);
      expect(vigente, findsOneWidget);
      expect(tester.getSize(quitar).height, greaterThanOrEqualTo(48));
    });
  });
}
