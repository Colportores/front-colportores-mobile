// QA #720 (PR #721): «Entregas pendientes» pasó a `ListView.builder`. El rótulo de cada tarjeta es un
// provider `autoDispose`: al salir de pantalla se descarta y, al volver a verla, se vuelve a leer de
// la base. Con la lectura lenta (unos milisegundos reales), la tarjeta que ya tenía nombre muestra
// «Persona sin nombre» un instante cada vez que se desplaza hasta ella.
//
// El hallazgo va con `QA_HALLAZGOS=true` (dart-define): sin eso queda saltado.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/entrega_diferida_providers.dart'
    show rotuloDeEntregaProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  testWidgets(
    'volver a una tarjeta que ya tenía nombre no muestra «Persona sin nombre» mientras lee su rótulo',
    (tester) async {
      final e = EntornoDeEntrega()
        ..entregas.emitirPendientes([
          for (var i = 0; i < 60; i++)
            pendienteDe(
              'v-$i',
              fecha: DateTime(2026, 11, 1 + i % 25, 9),
              vinculo: 'ep-$i',
              lineas: [lineaDe('e-$i', 'p-hijos', 1 + i)],
            ),
        ]);
      e.ahora = ahoraDeLosTests;
      // Cada lectura del rótulo queda esperando hasta que el test la libera (la base tarda).
      final lecturas = <Completer<void>>[];
      var pedidas = 0;
      Future<void> liberar() async {
        // Primero se arma lo que falte (la lista, las tarjetas) y recién ahí se libera cada lectura.
        await tester.pump();
        await tester.pump();
        for (final c in lecturas) {
          if (!c.isCompleted) c.complete();
        }
        lecturas.clear();
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...e.overrides,
            rotuloDeEntregaProvider.overrideWith((ref, quien) async {
              final lectura = Completer<void>();
              lecturas.add(lectura);
              pedidas++;
              await lectura.future;
              return (persona: 'Persona ${quien.espacioPersonaId}', direccion: 'Grecia 3310');
            }),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: const EntregasPendientesPage(colportorId: 'col-1'),
          ),
        ),
      );
      await liberar();
      expect(find.textContaining('Persona sin nombre'), findsNothing);

      final lista = find.byKey(const Key('entregas_lista'));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: lista, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await liberar();
      expect(find.textContaining('Persona sin nombre'), findsNothing);

      // Se vuelve a las primeras: se arman de nuevo y piden su rótulo otra vez.
      final antes = pedidas;
      scroll.position.jumpTo(0);
      await tester.pump();
      // Las tarjetas de arriba vuelven a pedir su rótulo a la base (el provider se había descartado).
      expect(pedidas, greaterThan(antes));

      expect(
        find.textContaining('Persona sin nombre'),
        findsNothing,
        reason: 'la tarjeta que ya tenía nombre muestra «Persona sin nombre» al volver a verla',
      );
      await liberar();
      expect(find.textContaining('Persona sin nombre'), findsNothing);
    },
    skip: !_hallazgos,
  );
}
