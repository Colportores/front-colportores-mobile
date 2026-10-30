// QA de #428, revisión visual: el recorrido de «Sí, registrar la venta» con las fuentes reales del
// proyecto (sin ellas `flutter_test` pinta cajas y las medidas de layout mienten) a 360×640 y 412×915,
// con letra 1,0× y 2,0×. Sin overflow en ningún estado; con `--dart-define=QA_CAPTURAS=true` saca los
// PNG a `.dart_tool/qa_capturas/` (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_cuando_cobrar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;
import '../../helpers/qa_vista39_venta_428_arnes.dart';
import '../../helpers/venta_ui_falsos.dart' show tocar;

Future<void> _foto(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa428_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  setUpAll(cargarTipografias);

  for (final tamano in const [Size(360, 640), Size(412, 915)]) {
    for (final escala in const [1.0, 2.0]) {
      final etiqueta = '${tamano.width.toInt()}x${tamano.height.toInt()}_${escala}x';

      testWidgets(
        'recorrido a $etiqueta: sin overflow en R·06, la venta, la pregunta y los avisos',
        (tester) async {
          final a = Arnes428();
          await a.montar(tester, tamano: const Size(390, 1600));
          tester.view.physicalSize = tamano;
          a.escala.value = escala;
          await tester.pumpAndSettle();

          // R·06
          await a.tocarKey(tester, const Key('abrir'));
          await a.tocarKey(tester, ClavesEntrevista.finalizar);
          expect(tester.takeException(), isNull, reason: 'R·06');
          await _foto(tester, '${etiqueta}_1_r06');

          // La venta con la persona y la casa puestas.
          await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
          expect(tester.takeException(), isNull, reason: 'venta');
          await _foto(tester, '${etiqueta}_2_venta');
          // Un aviso largo, con la venta a medias: «atrás» → «Salir».
          tester.view.physicalSize = const Size(390, 1600);
          a.escala.value = 1;
          await tester.pumpAndSettle();
          await a.armarLaVenta(tester);
          tester.view.physicalSize = tamano;
          a.escala.value = escala;
          await tester.pumpAndSettle();
          await a.registrar(tester);

          // «¿Cuándo volvés a cobrar?»
          expect(tester.takeException(), isNull, reason: 'pregunta');
          await _foto(tester, '${etiqueta}_3_pregunta');

          // «Día y hora»
          await a.tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.manana));
          expect(tester.takeException(), isNull, reason: 'día y hora');
          await _foto(tester, '${etiqueta}_4_dia_y_hora');

          // Cobranza agendada.
          await tocar(tester, find.byKey(const Key('agendar_hoja_listo')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: 'cobranza agendada');
          expect(find.textContaining('Cobranza agendada para'), findsOneWidget);
          await _foto(tester, '${etiqueta}_5_agendada');
        },
      );

      testWidgets('avisos a $etiqueta: la venta que no se guardó dice qué hacer y cabe entera', (
        tester,
      ) async {
        final a = Arnes428();
        await a.montar(tester, tamano: tamano, escala: escala);

        await a.tocarKey(tester, const Key('jornada'));
        await _foto(tester, '${etiqueta}_6_r06_jornada');
        await a.tocarKey(tester, ClavesEntrevista.filaSalida);
        await a.tocarKey(tester, const Key('hoja_hora_usar'));
        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
        await tocar(tester, find.byKey(const Key('venta_atras')));
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        final aviso = find.textContaining('Terminala para poder cerrar la jornada');
        expect(aviso, findsOneWidget);
        final caja = tester.getRect(aviso);
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(tamano.width));
        expect(caja.bottom, lessThanOrEqualTo(tamano.height));
        await _foto(tester, '${etiqueta}_7_aviso_jornada');
      });
    }
  }
}
