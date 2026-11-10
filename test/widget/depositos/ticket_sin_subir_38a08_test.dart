// 38A-08 «No pudimos enviar el ticket» (#443, decisión «Ticket dep.» del 10/11): la foto de un ticket
// de depósito no subió. El depósito ya quedó; el aviso lo dice en «Registrar depósito» y en Mi Cuenta,
// y «Reintentar ahora» hace una pasada de la cola sin perder nada. Y el chip de ACCIONES apagado con
// $ 0 en mano (P1 del QA de #443).
import 'dart:async';

import 'package:colportores_mobile/features/cuenta/presentation/textos_cuenta.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deposito_arnes.dart';

const _aviso = Key('deposito_ticket_sin_subir');
const _chip = Key('cuenta_registrar_deposito');

/// La cola de fotos de mentira: cuántos tickets no subieron y qué pasa al reintentar.
final class _Cola {
  final cuantos = StreamController<int>.broadcast();

  /// Las fechas de los depósitos con la foto rechazada para siempre.
  final rechazados = StreamController<List<DateTime>>.broadcast();
  var reintentos = 0;

  /// Lo que hace el próximo «Reintentar ahora»; por defecto, nada.
  Future<void> Function() alReintentar = () async {};

  List<Override> get overrides => [
    ticketsDeDepositoSinSubirProvider.overrideWith((ref) => cuantos.stream),
    ticketsDeDepositoRechazadosProvider.overrideWith((ref) => rechazados.stream),
    reintentarSubidaDeTicketsProvider.overrideWithValue(() {
      reintentos++;
      return alReintentar();
    }),
  ];

  Future<void> rechazar(WidgetTester tester, List<DateTime> fechas) async {
    rechazados.add(fechas);
    await tester.pump();
    await tester.pump();
  }

  Future<void> emitir(WidgetTester tester, int n) async {
    cuantos.add(n);
    await tester.pump();
    await tester.pump();
  }
}

Finder _reintentar() => find.descendant(of: find.byKey(_aviso), matching: find.byType(TextButton));

TextButton _boton(WidgetTester tester) => tester.widget<TextButton>(_reintentar());

void main() {
  group('38A-08 en «Registrar depósito»', () {
    testWidgets('sin tickets trabados no hay aviso; con uno dice el texto del canvas', (
      tester,
    ) async {
      final cola = _Cola();
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.emitir(tester, 0);
      expect(find.byKey(_aviso), findsNothing);

      await cola.emitir(tester, 1);
      expect(find.byKey(_aviso), findsOneWidget);
      expect(
        find.text(
          'No pudimos enviar el ticket. Quedó guardado en el teléfono y lo reintentamos solo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar ahora'), findsOneWidget);
      expect(tester.getSize(_reintentar()).height, greaterThanOrEqualTo(48));
    });

    testWidgets('con dos, el plural', (tester) async {
      final cola = _Cola();
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.emitir(tester, 2);
      expect(find.text(TextosDeposito.ticketsSinSubir(2)), findsOneWidget);
      expect(TextosDeposito.ticketsSinSubir(2), startsWith('No pudimos enviar 2 tickets.'));
    });

    testWidgets('el aviso no frena registrar otro depósito', (tester) async {
      final cola = _Cola();
      final arnes = ArnesDeDeposito(extras: cola.overrides);
      await montarDeposito(tester, arnes);
      await cola.emitir(tester, 1);
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados, hasLength(1));
    });

    testWidgets('«Reintentar ahora» con doble toque hace una sola pasada y vuelve a habilitarse', (
      tester,
    ) async {
      final cola = _Cola();
      final tarda = Completer<void>();
      cola.alReintentar = () => tarda.future;
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.emitir(tester, 1);

      await tester.tap(_reintentar());
      await tester.pump();
      expect(_boton(tester).onPressed, isNull);
      await tester.tap(_reintentar(), warnIfMissed: false);
      await tester.pump();
      expect(cola.reintentos, 1);

      tarda.complete();
      await tester.pump();
      await tester.pump();
      expect(_boton(tester).onPressed, isNotNull);
    });

    testWidgets('si el reintento falla, el aviso sigue y el botón no queda trabado', (
      tester,
    ) async {
      final cola = _Cola()..alReintentar = () async => throw StateError('sin red');
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.emitir(tester, 1);

      await tester.tap(_reintentar());
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(_aviso), findsOneWidget);
      expect(_boton(tester).onPressed, isNotNull);

      await tester.tap(_reintentar());
      await tester.pump();
      expect(cola.reintentos, 2);
    });

    testWidgets('cuando la foto sube, el aviso se va solo', (tester) async {
      final cola = _Cola();
      cola.alReintentar = () async => cola.cuantos.add(0);
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.emitir(tester, 1);
      await tester.tap(_reintentar());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_aviso), findsNothing);
    });

    testWidgets('a 320 × 640 con el texto al 200 % entra y se lee entero', (tester) async {
      final cola = _Cola();
      await montarDeposito(
        tester,
        ArnesDeDeposito(extras: cola.overrides),
        tamano: const Size(320, 640),
        escala: 2,
      );
      await cola.emitir(tester, 1);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_aviso), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });

  group('38A-08 en Mi Cuenta', () {
    testWidgets('el aviso sale arriba de las tarjetas y «Reintentar ahora» anda', (tester) async {
      final cola = _Cola();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        overrides: ArnesDeDeposito(extras: cola.overrides).overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_aviso), findsNothing);

      await cola.emitir(tester, 1);
      expect(find.byKey(_aviso), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(_aviso)).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('cuenta_enMano'))).dy),
      );
      await tester.tap(_reintentar());
      await tester.pump();
      expect(cola.reintentos, 1);
    });

    testWidgets('a 320 × 640 con el texto al 200 % no desborda', (tester) async {
      final cola = _Cola();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        tamano: const Size(320, 640),
        escala: 2,
        overrides: ArnesDeDeposito(extras: cola.overrides).overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      await cola.emitir(tester, 3);
      expect(tester.takeException(), isNull);
      expect(find.text(TextosDeposito.ticketsSinSubir(3)), findsOneWidget);
    });
  });

  group('foto rechazada para siempre (P1 del 10/11)', () {
    const rechazo = Key('deposito_ticket_rechazado');
    final dia9 = DateTime.utc(2026, 11, 9, 15);
    final dia8 = DateTime.utc(2026, 11, 8, 15);

    testWidgets('en «Registrar depósito»: aviso aparte, con la fecha y sin «Reintentar»', (
      tester,
    ) async {
      final cola = _Cola();
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.rechazar(tester, const []);
      expect(find.byKey(rechazo), findsNothing);

      await cola.rechazar(tester, [dia9]);
      expect(
        find.text(
          'No pudimos enviar la foto del ticket del depósito del 09/11 y ya no se puede '
          'reintentar. Avisale a tu coordinador para que lo revise.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(rechazo), matching: find.byType(TextButton)),
        findsNothing,
      );
      // No es 38A-08: ese aviso no sale por una rechazada.
      expect(find.byKey(_aviso), findsNothing);
    });

    testWidgets('con varias, el plural', (tester) async {
      final cola = _Cola();
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.rechazar(tester, [dia8, dia9]);
      expect(
        find.text(
          'No pudimos enviar las fotos de 2 tickets de depósito y ya no se pueden reintentar. '
          'Avisale a tu coordinador para que los revise.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('los dos avisos juntos y registrar igual', (tester) async {
      final cola = _Cola();
      final arnes = ArnesDeDeposito(extras: cola.overrides);
      await montarDeposito(tester, arnes);
      await cola.emitir(tester, 1);
      await cola.rechazar(tester, [dia9]);
      expect(find.byKey(_aviso), findsOneWidget);
      expect(find.byKey(rechazo), findsOneWidget);
      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados, hasLength(1));
    });

    testWidgets('se va cuando ya no hay rechazadas', (tester) async {
      final cola = _Cola();
      await montarDeposito(tester, ArnesDeDeposito(extras: cola.overrides));
      await cola.rechazar(tester, [dia9]);
      expect(find.byKey(rechazo), findsOneWidget);
      await cola.rechazar(tester, const []);
      expect(find.byKey(rechazo), findsNothing);
    });

    testWidgets('en Mi Cuenta, a 320 × 640 con el texto al 200 %, entra y contrasta', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final cola = _Cola();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        tamano: const Size(320, 640),
        escala: 2,
        overrides: ArnesDeDeposito(extras: cola.overrides).overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(rechazo), findsNothing);
      await cola.rechazar(tester, [dia8, dia9]);
      expect(tester.takeException(), isNull);
      expect(find.byKey(rechazo), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  });

  group('ACCIONES con \$ 0 en mano (P1 del QA de #443)', () {
    testWidgets('«Registrar depósito» queda apagado y dice por qué', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
        overrides: ArnesDeDeposito().overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_chip));
      expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNull);
      expect(find.text('No tenés plata en mano para depositar.'), findsOneWidget);
      expect(TextosCuenta.sinPlataParaDepositar, 'No tenés plata en mano para depositar.');

      await tester.tap(find.byKey(_chip), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(TextosDeposito.titulo), findsNothing);
      expect(tester.getSize(find.byKey(_chip)).height, greaterThanOrEqualTo(48));
    });

    testWidgets('con plata en mano está prendido y sin motivo', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        overrides: ArnesDeDeposito().overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(find.byKey(_chip)).onPressed, isNotNull);
      expect(find.text(TextosCuenta.sinPlataParaDepositar), findsNothing);
    });

    testWidgets('apagado, a 320 × 640 con el texto al 200 %, se lee y contrasta', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
        tamano: const Size(320, 640),
        escala: 2,
        overrides: ArnesDeDeposito().overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(TextosCuenta.sinPlataParaDepositar));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  });
}
