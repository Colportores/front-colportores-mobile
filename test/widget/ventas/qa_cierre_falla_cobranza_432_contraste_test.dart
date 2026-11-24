// QA de #432 (ronda 3): contraste de texto del aviso «No pudimos agendar el cobro» en la tarjeta de
// «Así quedó la venta». Va aparte y con la letra de prueba: con las fuentes reales
// `textContrastGuideline` da falsos negativos.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/ventas/presentation/flujo_cuando_cobrar.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_venta_432_arnes.dart';

void main() {
  usarFuentesReales = false;

  testWidgets('el aviso de la falla en la tarjeta cumple el contraste de texto', (tester) async {
    final h = tester.ensureSemantics();
    tester.view.physicalSize = telefonoGrande;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AsiQuedoLaVentaPage.abrir(
                context,
                AsiQuedoLaVentaPage(
                  numeroTalonario: '0039',
                  persona: 'Pedro Gómez',
                  direccion: 'Grecia 3307',
                  descripcion: 'Colección de 1 libro',
                  totalCentavos: 300000,
                  entrega: EntregaDelCierre.completa,
                  cobradoCentavos: 220000,
                  saldoCentavos: 80000,
                  cobranza: const CobranzaSinFecha(),
                  alPonerFecha: () async => const CobranzaNoAgendada(),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ClavesCierreDeVenta.accionCobranza));
    await tester.pumpAndSettle();

    expect(find.byKey(ClavesCierreDeVenta.fallaCobranza), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    h.dispose();
  });
}
