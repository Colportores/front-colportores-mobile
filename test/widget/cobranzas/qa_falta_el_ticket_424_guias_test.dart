// Guías de accesibilidad de Flutter sobre la marca «Falta el ticket» del detalle del cobro (vista 30 B,
// #424), en 360x640 y 412x915, con texto 1,0 y 2,0. Con las cajas de Ahem la guía de contraste lee el
// color de verdad (con la fuente real da falsos negativos).
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/anular_cobro_arnes.dart';
import '../../helpers/qa_vista23_408_arnes.dart' show usarFuentesReales408;
import '../../helpers/ticket_tarjeta_arnes.dart';

DetalleDelCobro _tarjeta() =>
    detalleDeEjemplo(medio: MedioCobranza.tarjeta, numeroAprobacion: '004512');

void main() {
  usarFuentesReales408 = false;
  for (final tamano in const [Size(360, 640), Size(412, 915)]) {
    for (final escala in const [1.0, 2.0]) {
      for (final (rotulo, conCamara, ahora) in [
        ('con cámara', true, null),
        ('sin cámara', false, null),
        ('pasadas las 72 h', true, DateTime.utc(2026, 10, 27)),
      ]) {
        group('$rotulo · ${tamano.width.toInt()}x${tamano.height.toInt()} x$escala', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            await montarDetalleDelCobro(
              tester,
              repo: AnulacionesEnMemoria(cobros: [_tarjeta()]),
              overrides: overridesDeTicket(nuevoArnesTicket(), conCamara: conCamara),
              escala: escala,
              tamano: tamano,
              ahora: ahora,
            );
            // La lista es perezosa: con letra grande la marca puede quedar fuera de lo armado.
            await traerAlAlcance(tester, find.byKey(const Key('detalle_cobro_falta_ticket')));
            expect(find.byKey(const Key('detalle_cobro_falta_ticket')), findsOneWidget);
            await expectLater(tester, meetsGuideline(guia));
            expect(tester.takeException(), isNull);
            h.dispose();
          }

          testWidgets(
            'tamaño de toque Android (48 dp)',
            (t) => verificar(t, androidTapTargetGuideline),
          );
          testWidgets('tamaño de toque iOS (44 pt)', (t) => verificar(t, iOSTapTargetGuideline));
          testWidgets(
            'todo lo tocable tiene nombre',
            (t) => verificar(t, labeledTapTargetGuideline),
          );
          testWidgets('contraste del texto', (t) => verificar(t, textContrastGuideline));
        });
      }
    }
  }
}
