// Mi Cuenta (vista 33A·01, #388): la acción «Cargar ticket» y la fila «Mis tickets · N por validar ›»,
// que son las puertas de la vista 38.
import 'package:colportores_mobile/features/cuenta/presentation/textos_cuenta.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deposito_arnes.dart';
import '../../helpers/historial_tickets_arnes.dart';

const _fila = Key('cuenta_mis_tickets');

Finder get _valorDeLaFila =>
    find.descendant(of: find.byKey(_fila), matching: find.textContaining('por validar'));

Future<void> _verLaFila(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_fila));
  await tester.pump();
}

void main() {
  group('la fila «Mis tickets»', () {
    testWidgets('dice cuántos esperan validación (los de la cola también) y abre «Mis tickets»', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba('d1'),
          itemDePrueba('d2', estado: EstadoDelItem.enCola),
          ...filasDelCanvas().skip(2),
        ]),
      );
      await montarCuenta(
        tester,
        arnes.cuenta,
        overrides: [
          ...arnes.overridesSinCuenta,
          historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await _verLaFila(tester);

      expect(find.text('Mis tickets'), findsOneWidget);
      expect(find.text('2 por validar'), findsOneWidget);

      await tester.tap(find.byKey(_fila));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tickets_pagina')), findsOneWidget);
      expect(find.byKey(const Key('tickets_fila_d1')), findsOneWidget);
    });

    testWidgets('con todo validado no dice nada de validar, pero la fila está', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable(inicial: historialCon(filasDelCanvas().skip(2).toList()));
      await montarCuenta(
        tester,
        arnes.cuenta,
        overrides: [
          ...arnes.overridesSinCuenta,
          historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await _verLaFila(tester);

      expect(find.byKey(_fila), findsOneWidget);
      expect(_valorDeLaFila, findsNothing);
    });

    testWidgets('si el historial no se puede leer la fila sigue, sin número', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable()..fallaAlSuscribir = true;
      await montarCuenta(
        tester,
        arnes.cuenta,
        overrides: [
          ...arnes.overridesSinCuenta,
          historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await _verLaFila(tester);

      expect(find.byKey(_fila), findsOneWidget);
      expect(_valorDeLaFila, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el número cambia solo cuando baja una validación', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1'), itemDePrueba('d2')]),
      );
      await montarCuenta(
        tester,
        arnes.cuenta,
        overrides: [
          ...arnes.overridesSinCuenta,
          historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await _verLaFila(tester);
      expect(find.text('2 por validar'), findsOneWidget);

      repo.emitir(
        historialCon([itemDePrueba('d1', estado: EstadoDelItem.validado), itemDePrueba('d2')]),
      );
      await tester.pump();

      expect(find.text('1 por validar'), findsOneWidget);
    });

    testWidgets('un doble toque abre una sola vez «Mis tickets»', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable(inicial: historialCon(filasDelCanvas()));
      await montarCuenta(
        tester,
        arnes.cuenta,
        overrides: [
          ...arnes.overridesSinCuenta,
          historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await _verLaFila(tester);

      await tester.tap(find.byKey(_fila));
      await tester.tap(find.byKey(_fila), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tickets_pagina')), findsOneWidget);

      await tester.tap(find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tickets_pagina')), findsNothing, reason: 'no había dos');
      expect(find.byKey(const Key('cuenta_pestana')), findsOneWidget);
    });

    testWidgets('con el texto al 200 % en 320×568 la fila no desborda', (tester) async {
      final arnes = ArnesDeDeposito();
      final repo = HistorialControlable(
        inicial: historialCon(List.generate(12, (i) => itemDePrueba('d$i'))),
      );
      await montarCuenta(
        tester,
        arnes.cuenta,
        tamano: const Size(320, 568),
        escala: 2,
        overrides: [
          ...arnes.overridesSinCuenta,
          historialDeTicketsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await _verLaFila(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('12 por validar'), findsOneWidget);
    });
  });

  group('la acción «Cargar ticket»', () {
    testWidgets('abre el mismo formulario que «Registrar depósito»', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarCuenta(tester, arnes.cuenta, overrides: arnes.overridesSinCuenta);

      await tester.ensureVisible(find.byKey(const Key('cuenta_cargar_ticket')));
      await tester.tap(find.byKey(const Key('cuenta_cargar_ticket')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);
    });

    testWidgets('un doble toque abre un solo formulario', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarCuenta(tester, arnes.cuenta, overrides: arnes.overridesSinCuenta);

      await tester.ensureVisible(find.byKey(const Key('cuenta_cargar_ticket')));
      await tester.tap(find.byKey(const Key('cuenta_cargar_ticket')));
      await tester.tap(find.byKey(const Key('cuenta_cargar_ticket')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);

      await tester.tap(find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing, reason: 'no había dos');
    });

    testWidgets('sin efectivo en mano queda apagada y el motivo se dice una sola vez', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(
        cuenta: RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
      );
      await montarCuenta(tester, arnes.cuenta, overrides: arnes.overridesSinCuenta);
      await tester.ensureVisible(find.byKey(const Key('cuenta_cargar_ticket')));
      await tester.pump();

      final boton = tester.widget<OutlinedButton>(find.byKey(const Key('cuenta_cargar_ticket')));
      expect(boton.onPressed, isNull);
      expect(find.text(TextosCuenta.sinPlataParaDepositar), findsOneWidget);

      await tester.tap(find.byKey(const Key('cuenta_cargar_ticket')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
    });
  });
}
