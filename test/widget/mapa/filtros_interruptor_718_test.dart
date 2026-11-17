// «Mostrar bajas» de los filtros de la Lista y el interruptor apagado a 3:1 (WCAG 1.4.11; decisión del
// 17/11, P2 del QA de #715; revisión de #718): la hoja no trae colores propios para el apagado, así
// que el borde y el pulgar son los del `switchTheme` (el gris de la paleta).
import 'package:colportores_mobile/core/theme/colores_colportaje.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lista_ubicaciones_arnes.dart';

void main() {
  testWidgets('apagado, sin colores propios que le ganen al tema: borde y pulgar en gris', (
    tester,
  ) async {
    await montarLista(tester);
    await abrirHojaFiltros(tester);
    final interruptor = find.descendant(
      of: find.byKey(const Key('hoja_filtros_bajas')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(interruptor);

    final widget = tester.widget<Switch>(interruptor);
    expect(widget.value, isFalse);
    expect(widget.inactiveThumbColor, isNull);
    expect(widget.inactiveTrackColor, isNull);
    expect(widget.trackOutlineColor, isNull);
    expect(widget.thumbColor, isNull);
    final tema = Theme.of(tester.element(interruptor)).switchTheme;
    expect(tema.trackOutlineColor!.resolve(const {}), ColoresColportaje.unica.gris);
    expect(tema.thumbColor!.resolve(const {}), ColoresColportaje.unica.gris);
  });
}
