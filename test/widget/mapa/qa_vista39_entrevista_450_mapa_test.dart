// QA de #450 sobre el mapa real (vista 06 con el aviso fijo de la entrevista en curso, vista 39 R·05):
// a 360×640 y 412×915, con la letra a 1,0 y a 2,0, el aviso no desborda, no tapa los botones del mapa
// y lleva de vuelta a la hoja de la entrevista.
//
// Capturas: `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, ignorado por git).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrevista_falsos.dart';
import '../../helpers/qa_vista39_450_arnes.dart'
    show cargarFuentes, conCapturas, escalas39, tamanos39;
import 'mapa_ubicaciones_arnes.dart';

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa450_mapa_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  late MontajeEntrevista entrevista;

  // Control: el mismo mapa sin entrevista, para saber si un hallazgo es del aviso o ya estaba.
  testWidgets('control sin entrevista · 360x640_x2: «Referencias» a tamaño de toque', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await cargarFuentes(tester);
    await montarMapaUbicaciones(tester, escala: 2, tamano: const Size(360, 640));
    await asentarLista(tester);

    await _capturar(tester, 'control_360x640_x2');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantica.dispose();
  });

  setUp(() => entrevista = MontajeEntrevista());

  for (final tamano in tamanos39) {
    for (final escala in escalas39) {
      final celda = '${tamano.width.toInt()}x${tamano.height.toInt()}_x${escala.toInt()}';

      testWidgets('mapa con el aviso fijo · $celda: sin overflow, a tamaño de toque y etiquetado', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await cargarFuentes(tester);
        await entrevista.almacen.guardar(entrevistaDePrueba());
        await montarMapaUbicaciones(
          tester,
          overridesExtra: entrevista.overrides,
          escala: escala,
          tamano: tamano,
        );
        await asentarLista(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
        await _capturar(tester, 'aviso_$celda');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantica.dispose();
      });

      testWidgets('el aviso lleva a R·05 sobre el mapa · $celda y al volver el aviso sigue', (
        tester,
      ) async {
        await cargarFuentes(tester);
        await entrevista.almacen.guardar(entrevistaDePrueba());
        await montarMapaUbicaciones(
          tester,
          overridesExtra: entrevista.overrides,
          escala: escala,
          tamano: tamano,
        );
        await asentarLista(tester);

        await tester.tap(find.byKey(ClavesEntrevista.avisoFijo));
        await asentarLista(tester);
        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'hoja_r05_$celda');

        await tester.binding.handlePopRoute();
        await asentarLista(tester);

        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
        expect(find.textContaining(TextosEntrevista.enCursoTitulo), findsWidgets);
      });
    }
  }
}
