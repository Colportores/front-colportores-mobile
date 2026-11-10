// QA de #655 (vista 41, entrega 1): las guías de accesibilidad de Flutter en los 11 artboards —
// tamaño de toque de Android y de iOS, nombre en todo lo que se toca— a 360x640 y 412x915, con
// texto 1,0 y 2,0. El contraste va aparte (con las fuentes reales da falsos negativos).
//
// Hallazgo (con `skip`, `QA_HALLAZGOS=true` lo corre): el velo que cubre el mapa en N·02, «Elegí la
// ciudad» y «Crear igual» es un nodo tocable a pantalla completa sin nombre. Las guías de la matriz lo
// dejan afuera (para no tapar lo demás) y el test del velo lo pide aparte.
import 'package:colportores_mobile/features/mapa/presentation/widgets/alta_sobre_el_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista41_655_arnes.dart';

/// Las fallas de [guia] sin contar el nodo del velo (el que ocupa la pantalla entera).
Future<List<String>> _fallas(WidgetTester tester, AccessibilityGuideline guia, Size tamano) async {
  final evaluacion = await guia.evaluate(tester);
  if (evaluacion.passed) return const [];
  final velo = 'Rect.fromLTRB(0.0, 0.0, ${tamano.width}, ${tamano.height})';
  return [
    for (final f in evaluacion.reason!.split(RegExp(r'\n(?=SemanticsNode#)')))
      if (!f.contains(velo)) f,
  ];
}

/// Las fallas de [guia] que se repiten con la hoja arriba y con la hoja abajo (lo cortado por el
/// borde del scroll cambia de lugar y no cuenta).
Future<List<String>> _fallasReales(
  WidgetTester tester,
  AccessibilityGuideline guia,
  Size tamano,
) async {
  final desplazable = find.descendant(of: hojaAlta655, matching: find.byType(Scrollable)).first;
  final posicion = tester.state<ScrollableState>(desplazable).position;
  String clave(String f) => RegExp(r'label: "([^"]*)"').firstMatch(f)?.group(1) ?? f;

  posicion.jumpTo(0);
  await tester.pump();
  final arriba = await _fallas(tester, guia, tamano);
  posicion.jumpTo(posicion.maxScrollExtent);
  await tester.pump();
  final abajo = {for (final f in await _fallas(tester, guia, tamano)) clave(f)};
  return [
    for (final f in arriba)
      if (abajo.contains(clave(f))) f,
  ];
}

void main() {
  for (final a in Artboard655.values) {
    for (final tamano in tamanos655) {
      for (final escala in escalas655) {
        final nombre = '${a.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala';
        testWidgets('guías de toque y de nombre: $nombre', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA655(tester, a, tamano: tamano, escala: escala);
          await tester.pump(const Duration(milliseconds: 300));
          // Un nodo cortado por el borde del scroll de la hoja da un falso negativo: se mide con la
          // hoja arriba y abajo, y solo cuenta lo que falla en las dos posiciones.
          for (final guia in [
            androidTapTargetGuideline,
            iOSTapTargetGuideline,
            labeledTapTargetGuideline,
          ]) {
            expect(await _fallasReales(tester, guia, tamano), isEmpty);
          }
          semantica.dispose();
        });
      }
    }
  }

  for (final a in [Artboard655.a04, Artboard655.a04b, Artboard655.b03]) {
    testWidgets('el velo no es un nodo tocable sin nombre: ${a.rotulo}', (tester) async {
      final semantica = tester.ensureSemantics();
      await llegarA655(tester, a);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(ClavesAltaMapa.velo), findsOneWidget);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    }, skip: !verHallazgos655);
  }
}
