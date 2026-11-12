// QA #186 (HU-SYNC-006): casos límite de las pantallas 34·07 / 34·08 con respaldos sin abrir.
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`).
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_recuperacion_175_arnes.dart';
import '../../helpers/qa_vista23_408_arnes.dart' show cargarFuentes408;

final _aviso = find.byKey(const Key('recuperacion_sin_abrir'));

Future<ArnesRecuperacion> _llegar(
  WidgetTester tester,
  InformeRecuperacion informe, {
  Size tamano = chico175,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  final a = ArnesRecuperacion();
  a.servicio.resultado = RecuperacionHecha(informe);
  await abrirAsistente175(tester, a, tamano: tamano, escala: escala);
  await abrirCopia175(tester);
  await tester.pump(const Duration(milliseconds: 400));
  return a;
}

void main() {
  for (final tamano in [chico175, grande175]) {
    for (final escala in [1.0, 2.0]) {
      final suf = sufijo175(tamano, escala);

      testWidgets('34·08 con 1 sin abrir · $suf: sin overflow ni texto cortado, aviso a la vista', (
        tester,
      ) async {
        final a = await _llegar(
          tester,
          informeDePrueba(sinAbrir: 1),
          tamano: tamano,
          escala: escala,
        );
        await capturar175(tester, 'sinabrir_c08_1_$suf');
        expect(tester.takeException(), isNull);
        sinTextoCortado175(tester);
        await tester.ensureVisible(_aviso);
        expect(_aviso, findsOneWidget);
        await liberar175(tester, a);
      });

      testWidgets('34·07 con 2 sin abrir · $suf: sin overflow ni texto cortado, CTA a la mano', (
        tester,
      ) async {
        final a = await _llegar(
          tester,
          informeDePrueba(parcial: true, restauradas: 13, sinAbrir: 2),
          tamano: tamano,
          escala: escala,
        );
        await capturar175(tester, 'sinabrir_c07_2_$suf');
        expect(tester.takeException(), isNull);
        sinTextoCortado175(tester);
        await tester.ensureVisible(cta);
        expect(cta, findsOneWidget);
        await liberar175(tester, a);
      });

      testWidgets('34·08 con 12 sin abrir · $suf: sin overflow', (tester) async {
        final a = await _llegar(
          tester,
          informeDePrueba(sinAbrir: 12),
          tamano: tamano,
          escala: escala,
        );
        await capturar175(tester, 'sinabrir_c08_12_$suf');
        expect(tester.takeException(), isNull);
        sinTextoCortado175(tester);
        await liberar175(tester, a);
      });
    }
  }

  testWidgets('el aviso es una región viva (el lector de pantalla lo anuncia)', (tester) async {
    final h = tester.ensureSemantics();
    final a = await _llegar(tester, informeDePrueba(sinAbrir: 2));
    final nodo = tester.getSemantics(
      find.descendant(of: _aviso, matching: find.byType(Semantics)).first,
    );
    // El contenedor vivo más cercano al aviso.
    final n = tester.getSemantics(_aviso);
    var viva = false;
    SemanticsNode? cur = n;
    while (cur != null) {
      // ignore: deprecated_member_use
      if (cur.hasFlag(SemanticsFlag.isLiveRegion)) viva = true;
      cur = cur.parent;
    }
    expect(viva, isTrue, reason: 'nodo: ${nodo.label}');
    await liberar175(tester, a);
    h.dispose();
  });

  testWidgets('dado un informe con sin abrir negativo, no se muestra el aviso', (tester) async {
    final a = await _llegar(tester, informeDePrueba(sinAbrir: -1));
    expect(_aviso, findsNothing);
    await liberar175(tester, a);
  });

  testWidgets('el aviso no pisa el texto de lo recuperado: título, filas y CTA siguen', (
    tester,
  ) async {
    final a = await _llegar(tester, informeDePrueba(sinAbrir: 2));
    expect(tester.widget<Text>(titulo).data, 'Tus datos están de vuelta');
    expect(find.text('Ir a mi inicio'), findsOneWidget);
    await liberar175(tester, a);
  });
}
