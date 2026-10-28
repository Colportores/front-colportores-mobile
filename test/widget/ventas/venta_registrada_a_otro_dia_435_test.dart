// HU-VEN-003 (#435): el empalme 27A·14 → 27C·01. «Entregar otro día» de «Venta registrada» abre
// «Entregar otro día» con la venta recién guardada, y al guardar vuelve con la entrega. El armado real
// de la pila de la venta es de #428; este test fija el contrato que ese armado tiene que cumplir:
// `conEntregarOtroDia: true` y, ante `MomentoDeEntrega.otroDia`, empujar `EntregarOtroDiaPage.ruta`.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/ventas/presentation/pages/entregar_otro_dia_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/venta_registrada_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

void main() {
  testWidgets('«Entregar otro día» de 27A·14 abre 27C·01 y, al guardar, la entrega queda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final e = EntornoDeEntrega();
    e.ahora = ahoraDeLosTests;
    e.entregas.respuestaDeDiferir = diferidaPara(DateTime(2026, 10, 29, 8, 30));
    final guardada = ventaConColeccion();
    final navegador = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesDeEntregaDiferida(e),
        child: MaterialApp(
          theme: temaClaro(),
          navigatorKey: navegador,
          home: VentaRegistradaPage(
            guardada: guardada,
            nombreDelCliente: 'María Fernández',
            conEntregarOtroDia: true,
            alTerminar: () {},
            alContinuar: (seguimiento) {
              if (seguimiento.entrega == MomentoDeEntrega.otroDia) {
                unawaited(
                  navegador.currentState!.push(
                    EntregarOtroDiaPage.ruta(
                      guardada: guardada,
                      nombreDelCliente: 'María Fernández',
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
    await asentar(tester);

    await tocar(tester, find.text('Entregar otro día'));
    await tocar(tester, find.text('Continuar'));

    expect(find.text('Entregar otro día'), findsOneWidget);
    expect(find.text('VENTA 0042'), findsOneWidget);

    await tocar(tester, find.byKey(const Key('entrega_campo_fecha')));
    await tester.tap(find.byKey(ClavesAgendarVisita.dia(1)));
    await tester.pump();
    await tester.tap(find.byKey(ClavesAgendarVisita.hojaListo));
    await asentar(tester);
    await tocar(tester, find.byKey(const Key('venta_cta')));

    expect(e.entregas.diferidas.single.ventaId, 'v-1');
    expect(find.textContaining('Entrega guardada para'), findsOneWidget);
  });
}
