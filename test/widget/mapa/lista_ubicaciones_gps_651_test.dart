// #651: el chip «Sin GPS · Activar GPS» de la Lista (el mapa todavía no pidió el GPS) con el texto
// agrandado y fuentes reales: no se sale de la pantalla y se puede tocar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_baja_205_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

void main() {
  testWidgets('dado «sinPedir» a 320×568 con el texto ×2.0, entonces el chip se parte en renglones '
      'y nada se sale de la pantalla', (tester) async {
    const tamano = Size(320, 568);
    final handle = tester.ensureSemantics();
    await cargarFuentes205(tester);
    var alMapa = 0;
    await montarLista(
      tester,
      tamano: tamano,
      escala: 2,
      gpsAbierto: false,
      alActivarGps: () => alMapa++,
    );

    expect(find.text('◎ Sin GPS · Activar GPS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectSinTextoFueraDeLosCostados205(tester, tamano);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.text('◎ Sin GPS · Activar GPS'));
    expect(alMapa, 1);
    handle.dispose();
  });
}
