// QA del aviso de la foto rechazada para siempre (#443, PR #686): contraste (`textContrastGuideline`) en
// los dos teléfonos y los dos tamaños de texto. Va aparte y sin fuentes reales: con ellas la guía da
// falsos negativos (lee el fondo de una captura con glifos reales).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/cuenta_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/depositos/presentation/pages/registrar_deposito_page.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/qa_vista33_deposito_443_arnes.dart';

final _fechas = [DateTime.utc(2026, 11, 8, 15), DateTime.utc(2026, 11, 9, 15)];

List<Override> _cola(int sinSubir, List<DateTime> rechazadas) => [
  ticketsDeDepositoSinSubirProvider.overrideWith((ref) => Stream.value(sinSubir)),
  ticketsDeDepositoRechazadosProvider.overrideWith((ref) => Stream.value(rechazadas)),
];

void main() {
  usarFuentesReales443 = false;

  for (final tamano in tamanos443) {
    for (final escala in escalas443) {
      final suf = sufijo443(tamano, escala);

      for (final (nombre, sinSubir, rechazadas) in [
        ('una rechazada', 0, [_fechas.last]),
        ('varias + 38A-08', 2, _fechas),
      ]) {
        testWidgets('contraste: Registrar depósito, $nombre · $suf', (tester) async {
          final semantica = tester.ensureSemantics();
          final arnes = ArnesDeDeposito();
          tester.view.physicalSize = tamano;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [...overrides443(arnes), ..._cola(sinSubir, rechazadas)],
              child: MaterialApp(
                theme: temaClaro(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                  child: child!,
                ),
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
          if (find.byKey(const Key('deposito_ticket_rechazado')).evaluate().isEmpty) {
            await verEnElFormulario(tester, const Key('deposito_ticket_rechazado'));
          }
          expect(find.byKey(const Key('deposito_ticket_rechazado')), findsOneWidget);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });

        testWidgets('contraste: Mi Cuenta, $nombre · $suf', (tester) async {
          final semantica = tester.ensureSemantics();
          final arnes = ArnesDeDeposito(extras: _cola(sinSubir, rechazadas));
          tester.view.physicalSize = tamano;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                resumenDeCuentaRepositoryProvider.overrideWithValue(
                  RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
                ),
                ...arnes.overridesSinCuenta,
              ],
              child: MaterialApp(
                theme: temaClaro(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                  child: child!,
                ),
                home: const Scaffold(body: CuentaPage(colportorId: 'col-1', activa: true)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('deposito_ticket_rechazado')), findsOneWidget);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }
  }
}
