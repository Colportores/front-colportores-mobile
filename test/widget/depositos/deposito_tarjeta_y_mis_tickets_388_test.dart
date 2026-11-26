// «Registrar depósito» con los campos del ticket de la vista 38A (#388): «Tarjeta» (débito, crédito o
// «No», regla R3 del 26/10: gana el canvas) y, al registrar, «Ver mis tickets» (38A-06).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/deposito_arnes.dart';
import '../../helpers/historial_tickets_arnes.dart';

Finder _texto(String t) => find.text(t, findRichText: true);

ArnesDeDeposito _arnes({HistorialControlable? historial}) => ArnesDeDeposito(
  extras: [
    historialDeTicketsRepositoryProvider.overrideWithValue(
      historial ?? HistorialControlable(inicial: historialCon(filasDelCanvas())),
    ),
  ],
);

/// Toca [clave] después de traerla a la vista, venga de arriba o de abajo del formulario.
Future<void> _tocar(WidgetTester tester, Key clave) async {
  await verEnElFormulario(tester, clave);
  await tester.ensureVisible(find.byKey(clave));
  await tester.pump();
  await tester.tap(find.byKey(clave));
  await tester.pump();
}

void main() {
  group('38A-01 · «Tarjeta»', () {
    testWidgets('el formulario dice «TARJETA» con débito, crédito y «No», y arranca en «No»', (
      tester,
    ) async {
      final arnes = _arnes();
      await montarDeposito(tester, arnes);
      await verEnElFormulario(tester, const Key('deposito_tarjeta_2'));

      expect(_texto(TextosDeposito.tarjeta), findsOneWidget);
      for (final t in [TextosDeposito.debito, TextosDeposito.credito, TextosDeposito.sinTarjeta]) {
        expect(_texto(t), findsOneWidget, reason: t);
      }
      expect(_texto(TextosDeposito.referencia), findsOneWidget, reason: 'Nº DE AUTORIZACIÓN');
      expect(TextosDeposito.referencia, 'Nº DE AUTORIZACIÓN');

      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      expect(arnes.tickets.guardados.single.ticket.tarjetaTipo, isNull, reason: '«No»: efectivo');
    });

    for (final (clave, tipo) in [
      ('deposito_tarjeta_0', TipoDeTarjeta.debito),
      ('deposito_tarjeta_1', TipoDeTarjeta.credito),
    ]) {
      testWidgets('con $clave el ticket lleva $tipo y no la marca', (tester) async {
        final arnes = _arnes();
        await montarDeposito(tester, arnes);
        await escribirMonto(tester, '1800');
        await sacarLaFoto(tester);
        await _tocar(tester, Key(clave));

        await tocarRegistrar(tester);

        expect(arnes.tickets.guardados.single.ticket.tarjetaTipo, tipo);
        // La marca («cuál») no se carga: el canvas no la dibuja.
        expect(arnes.tickets.guardados.single.ticket.tarjetaMarca, isNull);
      });
    }

    testWidgets(
      'el retiro por el coordinador no lleva ticket: sin «Tarjeta», aunque se la haya elegido antes',
      (tester) async {
        final arnes = _arnes();
        await montarDeposito(tester, arnes);
        await escribirMonto(tester, '1800');
        await _tocar(tester, const Key('deposito_tarjeta_1'));

        await _tocar(tester, const Key('deposito_destino_2'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deposito_tarjeta_1')), findsNothing);

        await tocarRegistrar(tester);

        expect(arnes.tickets.guardados, isEmpty);
        expect(arnes.depositos.guardados.single.ticketId, isNull);
      },
    );

    testWidgets('volver de retiro a banco conserva la tarjeta elegida', (tester) async {
      final arnes = _arnes();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await _tocar(tester, const Key('deposito_tarjeta_0'));
      await _tocar(tester, const Key('deposito_destino_2'));
      await _tocar(tester, const Key('deposito_destino_0'));

      await tocarRegistrar(tester);

      expect(arnes.tickets.guardados.single.ticket.tarjetaTipo, TipoDeTarjeta.debito);
    });

    testWidgets('«Reintentar» con la misma tarjeta repite el mismo depósito; con otra, es otro', (
      tester,
    ) async {
      final arnes = _arnes()
        ..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado(causa: 'SqliteException');
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);

      await tocarRegistrar(tester);
      expect(find.byKey(const Key('deposito_error')), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNotNull);

      await _tocar(tester, const Key('deposito_tarjeta_1'));
      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados.map((d) => d.id), ['d-1', 'd-2']);
      expect(arnes.tickets.guardados.last.ticket.tarjetaTipo, TipoDeTarjeta.credito);
    });

    testWidgets('con el texto al 200 % en 320×568 el campo cabe y se toca', (tester) async {
      final arnes = _arnes();
      await montarDeposito(tester, arnes, tamano: const Size(320, 568), escala: 2);
      await _tocar(tester, const Key('deposito_tarjeta_2'));

      expect(tester.takeException(), isNull);
    });
  });

  group('38A-06 · «Ver mis tickets»', () {
    Future<List<bool>> registrar(WidgetTester tester, ArnesDeDeposito arnes) async {
      final resultados = await montarDeposito(tester, arnes);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);
      return resultados;
    }

    testWidgets('al registrar se ofrece, junto a «Listo»', (tester) async {
      await registrar(tester, _arnes());

      expect(_texto(TextosDeposito.tituloRegistrado), findsOneWidget);
      expect(find.byKey(const Key('deposito_ver_mis_tickets')), findsOneWidget);
      expect(_texto(TextosDeposito.verMisTickets), findsOneWidget);
      expect(find.byKey(const Key('deposito_listo')), findsOneWidget);
    });

    testWidgets('lleva a «Mis tickets», cierra el formulario y devuelve «registrado»', (
      tester,
    ) async {
      final arnes = _arnes();
      final resultados = await registrar(tester, arnes);

      await tester.tap(find.byKey(const Key('deposito_ver_mis_tickets')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tickets_pagina')), findsOneWidget);
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
      expect(resultados, [true]);
      expect(arnes.depositos.guardados, hasLength(1), reason: 'no registra nada más');

      await volverAtras(tester);
      expect(find.byKey(const Key('abrir_deposito')), findsOneWidget);
    });

    testWidgets('un doble toque abre una sola vez «Mis tickets»', (tester) async {
      await registrar(tester, _arnes());

      await tester.tap(find.byKey(const Key('deposito_ver_mis_tickets')));
      await tester.tap(find.byKey(const Key('deposito_ver_mis_tickets')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tickets_pagina')), findsOneWidget);

      await volverAtras(tester);
      expect(find.byKey(const Key('tickets_pagina')), findsNothing, reason: 'no había dos');
      expect(find.byKey(const Key('abrir_deposito')), findsOneWidget);
    });

    testWidgets('«Listo» sigue cerrando sin abrir nada', (tester) async {
      final resultados = await registrar(tester, _arnes());

      await tester.tap(find.byKey(const Key('deposito_listo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tickets_pagina')), findsNothing);
      expect(resultados, [true]);
    });

    testWidgets('el retiro por el coordinador también lo ofrece: está en el historial', (
      tester,
    ) async {
      final arnes = _arnes();
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '700');
      await _tocar(tester, const Key('deposito_destino_2'));
      await tester.pumpAndSettle();
      await tocarRegistrar(tester);

      expect(find.byKey(const Key('deposito_ver_mis_tickets')), findsOneWidget);
    });

    testWidgets('con el texto al 200 % en 320×568 los dos botones del pie caben', (tester) async {
      final arnes = _arnes();
      await montarDeposito(tester, arnes, tamano: const Size(320, 568), escala: 2);
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('deposito_ver_mis_tickets')), findsOneWidget);
      expect(find.byKey(const Key('deposito_listo')), findsOneWidget);
    });
  });
}
