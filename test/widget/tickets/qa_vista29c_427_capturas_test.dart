// Capturas de la QA de «Foto del ticket de tarjeta» (#427, PR #601): cada estado a 360x640 y 412x915,
// con texto 1,0 y 2,0, con las fuentes reales y un ticket dibujado. Solo corren con
// `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/` (gitignored, nunca al commit).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista29c_427_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa601_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Un «ticket» PNG: papel blanco con renglones de texto, para ver cómo se acomoda la foto.
Future<Uint8List> _ticketPng(WidgetTester tester) async {
  final bytes = await tester.runAsync(() async {
    final grabador = ui.PictureRecorder();
    final lienzo = Canvas(grabador);
    lienzo.drawRect(const Rect.fromLTWH(0, 0, 300, 520), Paint()..color = const Color(0xFFFFFFFF));
    final renglones = [
      'COMERCIO S.A.',
      'Mataojo 2044',
      '-----------------------',
      'VENTA DEBITO / CREDITO',
      'VISA ****4512',
      'MONTO  \$ 1.200,00',
      'FECHA  23/10/2026',
      'APROBACION 004512',
    ];
    for (var i = 0; i < renglones.length; i++) {
      final p = TextPainter(
        text: TextSpan(
          text: renglones[i],
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 20,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(lienzo, Offset(14, 20 + i * 44.0));
    }
    final imagen = await grabador.endRecording().toImage(300, 520);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  setUpAll(cargarFuentes427);

  for (final estado in Estado427.values) {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets('captura ${estado.id} ${tam.nombre} t${escala.toInt()}', (tester) async {
          final png = await _ticketPng(tester);
          await llevarAlEstado427(tester, estado, tamano: tam, escala: escala, foto: png);
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await tester.pump(const Duration(milliseconds: 400));
          await _foto(tester, '${estado.id}_${tam.nombre}_t${escala.toInt()}');
          if (escala > 1) {
            // Con letra grande lo de abajo queda tapado por el botón: también se captura al final.
            await irAlFinal427(tester);
            await _foto(tester, '${estado.id}_${tam.nombre}_t${escala.toInt()}_fin');
          }
          expect(tester.takeException(), isNull);
        }, skip: !_conCapturas);
      }
    }
  }

  for (final tam in tamanos) {
    for (final escala in escalas) {
      testWidgets('captura 29A03 ${tam.nombre} t${escala.toInt()}', (tester) async {
        await llevarA29A03(tester, tamano: tam, escala: escala);
        await tester.pump(const Duration(milliseconds: 400));
        await _foto(tester, '29A03_${tam.nombre}_t${escala.toInt()}');
        expect(tester.takeException(), isNull);
      }, skip: !_conCapturas);
    }
  }
}
