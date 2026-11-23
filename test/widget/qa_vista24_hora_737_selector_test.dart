// QA de #737 (PR #744), segunda vuelta: el selector de hora del sistema con el tope de escala de texto
// (1,3) que se le puso para que no desborde. Se prueba con las letras reales (la altura del diálogo
// depende de ellas) en los tamaños de teléfono, con la letra del teléfono en 1,0 / 1,3 / 2,0 / 3,0, en
// el dial y en el teclado, y se mira que el resto de la pantalla no pierda la escala del teléfono.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/qa_hojas_teclado_324_arnes.dart' show conCapturas;
import '../helpers/qa_vista24_avisos_516_arnes.dart';

const _escalas = <double>[1.0, 1.3, 2.0, 3.0];

/// Los dos botones del selector del sistema (la prueba corre en inglés, el teléfono en es-UY): el
/// primero cancela y el segundo confirma.
final _botones = find.descendant(of: find.byType(Dialog), matching: find.byType(TextButton));
final _cancelar = _botones.first;
final _aceptar = _botones.last;

void _dentroDeLaPantalla(WidgetTester tester, Finder f, String que) {
  final r = tester.getRect(f);
  final pantalla = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(
    r.left,
    greaterThanOrEqualTo(pantalla.left - 0.5),
    reason: '$que se sale por la izquierda',
  );
  expect(r.right, lessThanOrEqualTo(pantalla.right + 0.5), reason: '$que se sale por la derecha');
  expect(r.top, greaterThanOrEqualTo(pantalla.top - 0.5), reason: '$que se sale por arriba');
  expect(r.bottom, lessThanOrEqualTo(pantalla.bottom + 0.5), reason: '$que se sale por abajo');
}

void main() {
  setUpAll(cargarFuentesReales);

  for (final tam in [...tamanos736, tamanoChico736]) {
    for (final escala in _escalas) {
      testWidgets(
        'selector de hora de Cuotas · ${tam.nombre} · texto ${escala}x: sin overflow, «OK» y '
        '«Cancelar» a la vista, tocables y con guías de toque',
        (tester) async {
          final semantica = tester.ensureSemantics();
          await llevarAlEstado736(tester, Estado736.preferencias, tamano: tam, escala: escala);
          await tocar736(tester, horaCuota736);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'el diálogo desborda en el dial');
          expect(_botones, findsNWidgets(2), reason: 'faltan «Cancelar» y «OK»');
          _dentroDeLaPantalla(tester, _cancelar, 'Cancelar');
          _dentroDeLaPantalla(tester, _aceptar, 'OK');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          // Con el teclado (el modo de «escribir la hora») tampoco desborda y «OK» sigue a mano.
          await tester.tap(find.byIcon(Icons.keyboard_outlined));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'el diálogo desborda con el teclado');
          _dentroDeLaPantalla(tester, _aceptar, 'OK (teclado)');
          _dentroDeLaPantalla(tester, _cancelar, 'Cancelar (teclado)');
          semantica.dispose();
        },
      );
    }
  }

  testWidgets('«Cancelar» cierra el selector sin cambiar la hora ni avisar nada a 2,0x', (
    tester,
  ) async {
    final telefono = await llevarAlEstado736(tester, Estado736.preferencias, escala: 2);
    await tocar736(tester, horaCuota736);
    await tester.pumpAndSettle();
    await tester.tap(_cancelar);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
    expect(tester.widget<Text>(horaCuotaValor736).data, '09:00');
    expect(telefono.avisos.avisos.horaCuota, const HoraDelAviso(9, 0));
    expect(errorGuardar736, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('elegir y guardar la hora a 2,0x y a 3,0x anda de punta a punta', (tester) async {
    for (final escala in [2.0, 3.0]) {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias, escala: escala);
      await tocar736(tester, horaCuota736);
      await tester.pumpAndSettle();
      await elegirHora736(tester, 6, 45);
      expect(tester.takeException(), isNull);
      expect(telefono.avisos.avisos.horaCuota, const HoraDelAviso(6, 45), reason: '${escala}x');
      await tester.ensureVisible(horaCuotaValor736);
      expect(tester.widget<Text>(horaCuotaValor736).data, '06:45');
    }
  });

  testWidgets('el tope vale solo dentro del selector: la pantalla conserva la letra del teléfono', (
    tester,
  ) async {
    await llevarAlEstado736(tester, Estado736.preferencias, escala: 2);
    await tester.ensureVisible(horaCuotaValor736);
    final fuente = tester.widget<Text>(horaCuotaValor736).style?.fontSize ?? 14;
    final antes = tester.getSize(horaCuotaValor736).height;

    await tocar736(tester, horaCuota736);
    await tester.pumpAndSettle();
    // La escala que ve el diálogo es la topada; la de la pantalla de atrás sigue en 2,0.
    final ctxDialogo = tester.element(find.text('OK'));
    expect(MediaQuery.textScalerOf(ctxDialogo).scale(fuente) / fuente, closeTo(1.3, 0.01));
    final ctxPantalla = tester.element(horaCuotaValor736);
    expect(MediaQuery.textScalerOf(ctxPantalla).scale(fuente) / fuente, closeTo(2.0, 0.01));

    await tester.tap(_cancelar);
    await tester.pumpAndSettle();
    expect(tester.getSize(horaCuotaValor736).height, closeTo(antes, 0.5));
  });

  testWidgets('con la letra al 100 % el selector no cambia (el tope no se nota)', (tester) async {
    await llevarAlEstado736(tester, Estado736.preferencias);
    await tester.ensureVisible(horaCuotaValor736);
    final fuente = tester.widget<Text>(horaCuotaValor736).style?.fontSize ?? 14;
    await tocar736(tester, horaCuota736);
    await tester.pumpAndSettle();
    final ctxDialogo = tester.element(find.text('OK'));
    expect(MediaQuery.textScalerOf(ctxDialogo).scale(fuente) / fuente, closeTo(1.0, 0.01));
    expect(MediaQuery.alwaysUse24HourFormatOf(ctxDialogo), isTrue);
  });

  testWidgets(
    'apagar «Recordatorios de agenda» con el servidor lento no borra el aviso de otra cosa que sale '
    'mientras tanto',
    (tester) async {
      final telefono = await llevarAlEstado736(tester, Estado736.preferencias);
      final demora = Completer<void>();
      telefono.avisos.guardadoDemorado = demora;
      await tocar736(tester, recordatorios736);
      await tester.pump();
      expect(telefono.preferencias.preferencias.activados, isFalse);

      // Mientras la copia del servidor viaja, sale un aviso que no es de este interruptor.
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).showSnackBar(const SnackBar(content: Text('Otro aviso importante')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Otro aviso importante'), findsOneWidget);

      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Otro aviso importante'), findsOneWidget);
    },
    // skip: QA #737 — `clearSnackBars()` de `_cambiarActivados` corre tras esperar al servidor (hasta
    // 20 s) y borra el aviso de otra cosa. Se saca el skip cuando se limpie antes de esperar.
    skip: true,
  );

  // Las capturas solo corren con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
  for (final tam in [tamano360x640, tamanoChico736]) {
    for (final escala in [1.0, 2.0, 3.0]) {
      testWidgets('captura del selector ${tam.nombre} t${escala.toInt()}', (tester) async {
        await llevarAlEstado736(tester, Estado736.preferencias, tamano: tam, escala: escala);
        await tocar736(tester, horaCuota736);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
          final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
          final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
          final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
          File(
            '${dir.path}/qa744_selector_${tam.nombre}_t${escala.toInt()}.png',
          ).writeAsBytesSync(bytes.buffer.asUint8List());
        });
      }, skip: !conCapturas);
    }
  }
}
