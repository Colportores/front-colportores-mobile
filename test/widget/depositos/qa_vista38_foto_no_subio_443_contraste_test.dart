// QA de 38A-08 y del chip apagado (#443, PR #683): contraste (`textContrastGuideline`) de cada estado en
// los dos teléfonos y los dos tamaños de texto. Va aparte y sin fuentes reales: con ellas la guía da
// falsos negativos (lee el fondo de una captura con glifos reales).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/cuenta_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/depositos/presentation/pages/registrar_deposito_page.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/qa_vista33_deposito_443_arnes.dart';

void main() {
  usarFuentesReales443 = false;

  for (final tamano in tamanos443) {
    final suf = sufijo443(tamano, 1);

    testWidgets('contraste: Registrar depósito con un ticket sin subir · $suf', (tester) async {
      final semantica = tester.ensureSemantics();
      final arnes = ArnesDeDeposito();
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides443(arnes),
            ticketsDeDepositoSinSubirProvider.overrideWith((ref) => Stream.value(1)),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('abrir_deposito'),
                  onPressed: () => RegistrarDepositoPage.abrir(context, colportorId: 'col-1'),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await abrirDeposito(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposito_ticket_sin_subir')), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    for (final (nombre, resumen, tickets) in [
      ('Mi Cuenta con aviso', resumenDelCanvas, 2),
      ('Mi Cuenta nueva: chip apagado', resumenCuentaNueva, 0),
    ]) {
      testWidgets('contraste: $nombre · $suf', (tester) async {
        final semantica = tester.ensureSemantics();
        final arnes = ArnesDeDeposito(
          extras: [ticketsDeDepositoSinSubirProvider.overrideWith((ref) => Stream.value(tickets))],
        );
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              resumenDeCuentaRepositoryProvider.overrideWithValue(
                RepositorioDeCuentaControlable(inicial: resumen),
              ),
              ...arnes.overridesSinCuenta,
            ],
            child: MaterialApp(
              theme: temaClaro(),
              home: const Scaffold(body: CuentaPage(colportorId: 'col-1', activa: true)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (tickets == 0) {
          await tester.ensureVisible(find.byKey(const Key('cuenta_registrar_deposito')));
          await tester.pump();
        }
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
