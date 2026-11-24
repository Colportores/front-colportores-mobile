// «Registrar depósito» y la campaña del alquiler (decisión «Alq. campaña», 25/10, HU-CTA-007, #389): con
// una campaña en curso se pone sola; con dos, el colportor elige a cuál paga; con la campaña decidida
// (desde «Mi alquiler») no se pregunta. Y los casos límite: doble toque, falla y reintento, cambiar de
// concepto y el texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/campania_para_el_pago.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/deposito_arnes.dart';

Finder _texto(String t) => find.text(t, findRichText: true);

const _dos = [
  CampaniaParaElPago(id: 'c-nueva', nombre: 'Primavera 2026'),
  CampaniaParaElPago(id: 'c-vieja', nombre: 'Otoño 2026'),
];

/// Escribe el monto y deja el depósito de alquiler como retiro (sin foto), a falta de elegir campaña.
Future<void> _alquilerPorRetiro(WidgetTester tester, {String monto = '700'}) async {
  await escribirMonto(tester, monto);
  await tester.tap(find.byKey(const Key('deposito_concepto_1')));
  await tester.tap(find.byKey(const Key('deposito_destino_2')));
  await tester.pumpAndSettle();
}

void main() {
  group('con una sola campaña en curso', () {
    testWidgets('el alquiler va a esa campaña sin preguntar cuál', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);

      expect(find.byKey(const Key('deposito_campania_0')), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNotNull);

      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados.single.campaniaId, 'camp-1');
    });
  });

  group('con dos campañas en curso', () {
    testWidgets('con «Casa editora» no se pregunta nada y no viaja campaña', (tester) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      await montarDeposito(tester, arnes);
      await escribirMonto(tester, '700');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();

      expect(find.byKey(const Key('deposito_campania_0')), findsNothing);
      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.concepto, ConceptoDeDeposito.casaEditora);
      expect(deposito.campaniaId, isNull);
    });

    testWidgets('con «Alquiler» pide elegir la campaña, con sus nombres, y no deja registrar hasta '
        'que elige', (tester) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);

      expect(_texto('CAMPAÑA'), findsOneWidget);
      expect(find.byKey(const Key('deposito_campania_0')), findsOneWidget);
      expect(_texto('Primavera 2026'), findsOneWidget);
      expect(_texto('Otoño 2026'), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNull);
      expect(_texto(TextosDeposito.faltaLaCampania), findsOneWidget); // la nota del botón
      // Sin tocar el botón todavía no se marca en rojo.
      expect(find.byKey(const Key('deposito_falta_campania')), findsNothing);
    });

    testWidgets('tocar el botón apagado marca la campaña que falta, sin registrar nada', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);

      await tester.tap(find.byKey(const Key('venta_cta')), warnIfMissed: false);
      await tester.pump();

      expect(find.byKey(const Key('deposito_falta_campania')), findsOneWidget);
      expect(arnes.depositos.guardados, isEmpty);
    });

    testWidgets('al elegir una, el botón se habilita y el depósito va a ESA campaña', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);

      await tester.tap(find.byKey(const Key('deposito_campania_1')));
      await tester.pump();
      expect(botonRegistrar(tester).onPressed, isNotNull);
      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.concepto, ConceptoDeDeposito.alquiler);
      expect(deposito.campaniaId, 'c-vieja');
    });

    testWidgets('se puede cambiar de idea: gana la última elegida', (tester) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);

      await tester.tap(find.byKey(const Key('deposito_campania_1')));
      await tester.tap(find.byKey(const Key('deposito_campania_0')));
      await tester.pump();
      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados.single.campaniaId, 'c-nueva');
    });

    testWidgets('pasar a «Casa editora» y volver a «Alquiler» no pierde la campaña elegida', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);
      await tester.tap(find.byKey(const Key('deposito_campania_1')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('deposito_concepto_0')));
      await tester.pump();
      expect(find.byKey(const Key('deposito_campania_0')), findsNothing);
      await tester.tap(find.byKey(const Key('deposito_concepto_1')));
      await tester.pump();

      expect(botonRegistrar(tester).onPressed, isNotNull);
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados.single.campaniaId, 'c-vieja');
    });

    testWidgets('un doble toque en «Registrar» guarda un solo depósito', (tester) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      arnes.depositos.espera = Completer<void>();
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);
      await tester.tap(find.byKey(const Key('deposito_campania_0')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('venta_cta')));
      await tester.tap(find.byKey(const Key('venta_cta')), warnIfMissed: false);
      await tester.pump();
      arnes.depositos.espera!.complete();
      await tester.pumpAndSettle();

      expect(arnes.depositos.guardados, hasLength(1));
    });

    testWidgets('si falla a mitad, la elección se conserva, el botón vuelve a andar y el reintento '
        'repite el mismo depósito en la misma campaña', (tester) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      arnes.depositos.fallarUnaVezCon = const FailureDepositoNoGuardado(causa: 'prueba');
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);
      await tester.tap(find.byKey(const Key('deposito_campania_1')));
      await tester.pump();

      await tocarRegistrar(tester);
      expect(find.byKey(const Key('deposito_error')), findsOneWidget);
      expect(botonRegistrar(tester).onPressed, isNotNull);

      await tocarRegistrar(tester);

      expect(arnes.depositos.guardados, hasLength(2));
      expect(arnes.depositos.guardados.map((d) => d.campaniaId), ['c-vieja', 'c-vieja']);
      expect(arnes.depositos.guardados.map((d) => d.id).toSet(), hasLength(1));
    });

    testWidgets('mientras se registra no se puede cambiar la campaña', (tester) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      arnes.depositos.espera = Completer<void>();
      await montarDeposito(tester, arnes);
      await _alquilerPorRetiro(tester);
      await tester.tap(find.byKey(const Key('deposito_campania_0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('venta_cta')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('deposito_campania_1')), warnIfMissed: false);
      await tester.pump();
      arnes.depositos.espera!.complete();
      await tester.pumpAndSettle();

      expect(arnes.depositos.guardados.single.campaniaId, 'c-nueva');
    });

    testWidgets('con nombres largos y el texto al 200 % las opciones se apilan y nada desborda', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(
        campanias: const [
          CampaniaParaElPago(
            id: 'c-1',
            nombre: 'Campaña de primavera del litoral norte con todas las ciudades 2026',
          ),
          CampaniaParaElPago(id: 'c-2', nombre: 'Campaña de otoño de Montevideo y Canelones 2026'),
        ],
      );
      await montarDeposito(tester, arnes, tamano: const Size(320, 568), escala: 2);
      await escribirMonto(tester, '700');
      await verEnElFormulario(tester, const Key('deposito_concepto_1'));
      await tester.ensureVisible(find.byKey(const Key('deposito_concepto_1')));
      await tester.tap(find.byKey(const Key('deposito_concepto_1')));
      await tester.pumpAndSettle();

      await verEnElFormulario(tester, const Key('deposito_campania_1'));
      await tester.tap(find.byKey(const Key('deposito_campania_1')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byKey(const Key('deposito_campania_1'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('deposito_campania_0'))).dy),
        reason: 'apiladas en una columna',
      );
    });
  });

  group('con la campaña decidida (viene de «Mi alquiler»)', () {
    testWidgets('abre con «Alquiler» puesto, dice de qué campaña es y no pregunta cuál', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(campanias: _dos);
      await montarDeposito(
        tester,
        arnes,
        concepto: ConceptoDeDeposito.alquiler,
        campaniaId: 'c-vieja',
      );

      expect(find.byKey(const Key('deposito_campania_0')), findsNothing);
      expect(find.byKey(const Key('deposito_sin_campania')), findsNothing);
      // «Mi alquiler» pone el nombre desde su propio dato; acá, sin él, no se inventa uno.
      expect(find.byKey(const Key('deposito_campania_decidida')), findsNothing);
    });

    testWidgets('el depósito va a la campaña decidida, aunque ya no esté «en curso»', (
      tester,
    ) async {
      final arnes = ArnesDeDeposito(campania: null);
      await montarDeposito(
        tester,
        arnes,
        concepto: ConceptoDeDeposito.alquiler,
        campaniaId: 'c-terminada',
      );
      await escribirMonto(tester, '700');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();

      expect(find.byKey(const Key('deposito_sin_campania')), findsNothing);
      expect(botonRegistrar(tester).onPressed, isNotNull);
      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.concepto, ConceptoDeDeposito.alquiler);
      expect(deposito.campaniaId, 'c-terminada');
    });

    testWidgets('si después cambia a «Casa editora», no viaja la campaña', (tester) async {
      final arnes = ArnesDeDeposito();
      await montarDeposito(tester, arnes, concepto: ConceptoDeDeposito.alquiler, campaniaId: 'c-1');
      await escribirMonto(tester, '700');
      await tester.tap(find.byKey(const Key('deposito_concepto_0')));
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();

      await tocarRegistrar(tester);

      final deposito = arnes.depositos.guardados.single;
      expect(deposito.concepto, ConceptoDeDeposito.casaEditora);
      expect(deposito.campaniaId, isNull);
    });
  });
}
