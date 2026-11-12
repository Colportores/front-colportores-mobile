// QA de las entradas a «Registrar depósito» (#443): el pie de «Mi plata» (33C·01 y 33C·02) y «ACCIONES» de
// Mi Cuenta (33A·01 y 33A·04) en los dos teléfonos y con el texto a 1,0 y 2,0, con las guías de toque, y el
// camino completo: entrar, registrar y volver.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/mi_plata_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/widgets/piezas_mi_plata.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/qa_vista33_deposito_443_arnes.dart';

const _boton = Key('mi_plata_registrar_deposito');
const _chip = Key('cuenta_registrar_deposito');

Future<void> _montarMiPlata(
  WidgetTester tester,
  CategoriaDeMiPlata abierta, {
  required Size tamano,
  required double escala,
}) async {
  await cargarFuentes443(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...ArnesDeDeposito().overrides,
        detalleDeMiPlataRepositoryProvider.overrideWithValue(
          RepositorioDeDetalleControlable(inicial: detalleDelCanvas),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: MiPlataPage(colportorId: 'col-1', abierta: abierta),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final tamano in tamanos443) {
    for (final escala in escalas443) {
      final sufijo = sufijo443(tamano, escala);

      for (final abierta in [CategoriaDeMiPlata.enMano, CategoriaDeMiPlata.porCobrar]) {
        testWidgets(
          'Mi plata con ${abierta.name} abierta, $sufijo: el pie se alcanza y cumple las guías',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await _montarMiPlata(tester, abierta, tamano: tamano, escala: escala);
            await tester.dragUntilVisible(
              find.byKey(_boton),
              find.byKey(const Key('mi_plata_lista')),
              const Offset(0, -200),
            );
            expect(tester.takeException(), isNull);
            expect(tester.getSize(find.byKey(_boton)).height, greaterThanOrEqualTo(48));
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await capturar443(tester, 'miplata_${abierta.name}_$sufijo');
            semantica.dispose();
          },
        );
      }

      for (final nueva in [false, true]) {
        testWidgets(
          'Mi Cuenta ${nueva ? 'nueva' : 'con datos'}, $sufijo: «ACCIONES» se alcanza y cumple las guías',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await cargarFuentes443(tester);
            await montarCuenta(
              tester,
              RepositorioDeCuentaControlable(
                inicial: nueva ? resumenCuentaNueva : resumenDelCanvas,
              ),
              tamano: tamano,
              escala: escala,
              overrides: ArnesDeDeposito().overridesSinCuenta,
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(_chip));
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(tester.getSize(find.byKey(_chip)).height, greaterThanOrEqualTo(48));
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await capturar443(tester, 'cuenta_${nueva ? 'nueva' : 'datos'}_$sufijo');
            semantica.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'Mi Cuenta → ACCIONES → registrar → Listo vuelve a Mi Cuenta sin dejar nada abierto',
    (tester) async {
      final arnes = ArnesDeDeposito();
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        overrides: arnes.overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_chip));
      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();

      await escribirMonto(tester, '1000');
      await tester.tap(find.byKey(const Key('deposito_destino_2')));
      await tester.pump();
      await tocarRegistrar(tester);
      expect(arnes.depositos.guardados, hasLength(1));

      await tester.tap(find.byKey(const Key('deposito_listo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
      expect(find.text(TextosDeposito.titulo), findsNothing);
      expect(find.byKey(_chip), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
