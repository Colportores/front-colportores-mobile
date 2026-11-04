// QA de la entrada a la vista 31 desde la ficha de la persona (32B, HU-VEN-004, #161, PR #589): la fila
// de la venta del historial ahora se toca. Tamaño de toque, etiqueta para el lector y desbordes en
// 360×640 y 412×915, texto 1,0 y 2,0.
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

void main() {
  const tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  for (final t in tamanos.entries) {
    for (final escala in const [1.0, 2.0]) {
      testWidgets('ficha con venta tocable · ${t.key} · ×$escala', (tester) async {
        final semantica = tester.ensureSemantics();
        final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha())
          ..conDevolucion = true;
        m.cuentas.cuenta = cuentaConSaldo;
        await montarFicha(tester, m, tamano: t.value, escala: escala);
        final venta = find.text('12/10 · VENTA 0042');
        await tester.scrollUntilVisible(venta, 300, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(venta);
        await tester.pump();
        expect(tester.takeException(), isNull);

        final fila = find.ancestor(of: venta, matching: find.byType(FilaDeHistorial)).first;
        expect(tester.getSize(fila).height, greaterThanOrEqualTo(48));
        final nodo = tester.getSemantics(fila);
        expect(nodo.flagsCollection.isButton, isTrue);
        expect(nodo.label, contains('VENTA 0042'));

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantica.dispose();
      });
    }
  }
}
