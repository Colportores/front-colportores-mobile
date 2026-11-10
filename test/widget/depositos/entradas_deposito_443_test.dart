// Por dónde se llega a «Registrar depósito» (#443): el pie de «Mi plata» con «En mano» o «Por cobrar»
// abiertos (33C·01 y 33C·02, decisión del 04/11) y «ACCIONES» de Mi Cuenta (33A·01).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/detalle_de_mi_plata.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/mi_plata_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/widgets/piezas_mi_plata.dart';
import 'package:colportores_mobile/features/depositos/presentation/textos_deposito.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deposito_arnes.dart';

Future<void> _montarMiPlata(
  WidgetTester tester,
  DetalleDeMiPlata detalle, {
  CategoriaDeMiPlata abierta = CategoriaDeMiPlata.enMano,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...ArnesDeDeposito().overrides,
        detalleDeMiPlataRepositoryProvider.overrideWithValue(
          RepositorioDeDetalleControlable(inicial: detalle),
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

const _boton = Key('mi_plata_registrar_deposito');

void main() {
  group('Mi plata', () {
    testWidgets('con «En mano» abierta, el pie abre «Registrar depósito» y vuelve', (tester) async {
      await _montarMiPlata(tester, detalleDelCanvas);

      await tester.tap(find.byKey(_boton));
      await tester.pumpAndSettle();
      expect(find.text(TextosDeposito.titulo), findsOneWidget);

      await tester.tap(find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();
      expect(find.byKey(_boton), findsOneWidget);
    });

    testWidgets('con «Por cobrar» abierta también (33C·02)', (tester) async {
      await _montarMiPlata(tester, detalleDelCanvas, abierta: CategoriaDeMiPlata.porCobrar);
      expect(find.byKey(_boton), findsOneWidget);
    });

    testWidgets('con «Depositado» sola, no; al abrir «En mano» aparece', (tester) async {
      await _montarMiPlata(tester, detalleDelCanvas, abierta: CategoriaDeMiPlata.depositado);
      expect(find.byKey(_boton), findsNothing);

      await tester.tap(find.byKey(const Key('mi_plata_categoria_enMano')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(_boton),
        find.byKey(const Key('mi_plata_lista')),
        const Offset(0, -200),
      );
      expect(find.byKey(_boton), findsOneWidget);
    });

    testWidgets('sin efectivo en la mano (33C·03) no hay nada que depositar', (tester) async {
      await _montarMiPlata(
        tester,
        const DetalleDeMiPlata(enManoCentavos: 0, enMano: [], porCobrarCentavos: 0, porCobrar: []),
      );
      expect(find.byKey(_boton), findsNothing);
    });

    testWidgets('dos toques seguidos abren una sola pantalla', (tester) async {
      await _montarMiPlata(tester, detalleDelCanvas);

      await tester.tap(find.byKey(_boton));
      await tester.tap(find.byKey(_boton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsOneWidget);

      await tester.tap(find.byKey(const Key('venta_atras')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_pagina')), findsNothing);
    });

    testWidgets('con el texto al 200 % el pie entra sin desbordar', (tester) async {
      await _montarMiPlata(tester, detalleDelCanvas, escala: 2);
      await tester.dragUntilVisible(
        find.byKey(_boton),
        find.byKey(const Key('mi_plata_lista')),
        const Offset(0, -200),
      );
      expect(find.byKey(_boton), findsOneWidget);
      expect(tester.getSize(find.byKey(_boton)).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });

  group('Mi Cuenta', () {
    testWidgets('«ACCIONES» lleva «Registrar depósito», de 48 dp, y lo abre', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        overrides: ArnesDeDeposito().overridesSinCuenta,
      );
      await tester.pumpAndSettle();

      final chip = find.byKey(const Key('cuenta_registrar_deposito'));
      expect(find.text('ACCIONES'), findsOneWidget);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));

      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text(TextosDeposito.titulo), findsOneWidget);
    });

    testWidgets('a 320 × 640 con el texto al 200 % las acciones entran', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        tamano: const Size(320, 640),
        escala: 2,
        overrides: ArnesDeDeposito().overridesSinCuenta,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
