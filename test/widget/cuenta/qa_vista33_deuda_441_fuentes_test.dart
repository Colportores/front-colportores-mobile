// QA de la deuda con la casa editora (vista 33A·01 y 33B, #441) con las fuentes reales de
// `assets/fonts/`: sin overflow ni texto cortado donde el ancho de verdad importa (con Ahem el ancho
// es falso) y, con `--dart-define=QA_CAPTURAS=true`, un PNG por estado en `.dart_tool/qa_capturas/`
// (no se commitean). Los contrastes están en `qa_vista33_deuda_441_test.dart`: con las fuentes reales
// `textContrastGuideline` da falsos negativos.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/deuda_casa_arnes.dart';
import '../../helpers/qa_vista33_deuda_441_arnes.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');
const _tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

void main() {
  for (final estado in EstadoQa33B.values) {
    for (final t in _tamanos.entries) {
      for (final esc in const [1.0, 2.0]) {
        testWidgets('33B · ${estado.name} · ${t.key} · ${esc}x: sin overflow con las fuentes '
            'reales${_capturar ? ' (y captura)' : ''}', (tester) async {
          await cargarFuentesReales(tester);
          final raiz = GlobalKey();
          await repoEnEstado(tester, estado, (repo) async {
            tester.view.physicalSize = t.value;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              ProviderScope(
                overrides: overridesDeDeuda(repo),
                child: RepaintBoundary(
                  key: raiz,
                  child: MaterialApp(
                    theme: temaClaro(),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(esc)),
                      child: child!,
                    ),
                    home: const DeudaCasaPage(colportorId: 'col-1'),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump();
            await tester.pump();
          });
          expect(tester.takeException(), isNull);
          if (_capturar) {
            await _capturarPng(tester, raiz, '441_33B_${estado.name}_${t.key}_x${esc.toInt()}');
          }
        });
      }
    }
  }

  for (final estado in EstadoQa33A.values) {
    for (final t in _tamanos.entries) {
      for (final esc in const [1.0, 2.0]) {
        testWidgets('33A · ${estado.name} · ${t.key} · ${esc}x: sin overflow con las fuentes '
            'reales${_capturar ? ' (y captura)' : ''}', (tester) async {
          await cargarFuentesReales(tester);
          await montarCuentaEnEstado(
            tester,
            estado,
            tamano: t.value,
            escala: esc,
            resumen: estado == EstadoQa33A.sinConexion ? resumenConDepositado441() : null,
          );
          expect(tester.takeException(), isNull);
          if (_capturar) {
            await _capturarPng(
              tester,
              GlobalKey(), // se captura la vista entera
              '441_33A_${estado.name}_${t.key}_x${esc.toInt()}',
              vistaEntera: true,
            );
          }
        });
      }
    }
  }
}

Future<void> _capturarPng(
  WidgetTester tester,
  GlobalKey raiz,
  String nombre, {
  bool vistaEntera = false,
}) async {
  Directory('.dart_tool/qa_capturas').createSync(recursive: true);
  await tester.runAsync(() async {
    final RenderRepaintBoundary r = vistaEntera
        ? tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first)
        : tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await r.toImage();
    final bd = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    File('.dart_tool/qa_capturas/$nombre.png').writeAsBytesSync(Uint8List.view(bd.buffer));
  });
}
