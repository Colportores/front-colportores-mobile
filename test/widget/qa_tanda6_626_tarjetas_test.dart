// QA de la tanda 6 de #537 (#626, PR #731): las dos tarjetas de «rótulo + valor» que pasan a dos
// renglones con texto grande (`TarjetaCuenta`, ficha 32B, y `TarjetaDeDatos`, devolución 31). El PR
// prueba 1,5 y 2,0; acá se barre toda la escala de 1,0 a 2,0 (cada 0,1) a 360 y 412 dp de ancho, que es
// donde los dos umbrales distintos (`> 16` y `> 20` sobre 14 sp) podían dejar un tramo roto: ninguna
// palabra del rótulo se parte a la mitad ni el valor baja a un segundo renglón, y no hay overflow.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_devolucion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

var _fuentes = false;
Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentes) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await c.load();
    }
  });
  _fuentes = true;
}

/// Ancho de [texto] en un solo renglón con [estilo] a la escala [escala].
double _ancho(String texto, TextStyle estilo, double escala) {
  final p = TextPainter(
    text: TextSpan(text: texto, style: estilo),
    textDirection: ui.TextDirection.ltr,
    textScaler: TextScaler.linear(escala),
  )..layout();
  return p.width;
}

Future<void> _montar(WidgetTester tester, Widget hijo, double ancho, double escala) async {
  tester.view.physicalSize = Size(ancho, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(ancho, 800), textScaler: TextScaler.linear(escala)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: hijo),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Verifica que el `Text` de [texto] no partió ninguna palabra ni (si [unRenglon]) bajó de renglón.
void _sinPartir(WidgetTester tester, String texto, double escala, {required bool unRenglon}) {
  final finder = find.text(texto);
  expect(finder, findsOneWidget, reason: 'falta «$texto»');
  final p = tester.renderObject<RenderParagraph>(finder);
  // El estilo efectivo (con la letra del tema), no solo el que el `Text` declara.
  final estilo = DefaultTextStyle.of(
    tester.element(finder),
  ).style.merge(tester.widget<Text>(finder).style);
  if (unRenglon) {
    expect(
      p.size.width + 0.5,
      greaterThanOrEqualTo(_ancho(texto, estilo, escala)),
      reason: '«$texto» a ×$escala bajó a otro renglón',
    );
  } else {
    final masLarga = texto.split(RegExp(r'[\s ]+')).map((w) => _ancho(w, estilo, escala));
    expect(
      p.size.width + 0.5,
      greaterThanOrEqualTo(masLarga.reduce((a, b) => a > b ? a : b)),
      reason: '«$texto» a ×$escala se partió a mitad de palabra',
    );
  }
}

void main() {
  const escalas = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0];
  const anchos = [360.0, 412.0];

  group('TarjetaCuenta (ficha 32B): rótulo y valor, toda la escala', () {
    const cuenta = ResumenCuentaPersona(
      compradoCentavos: 123456700,
      pagadoCentavos: 23456700,
      saldoCentavos: 100000000,
      entregasHechas: 12,
      entregasTotales: 12,
    );
    for (final ancho in anchos) {
      for (final escala in escalas) {
        testWidgets('${ancho.toInt()} dp × $escala', (tester) async {
          await _cargarFuentes(tester);
          await _montar(tester, const TarjetaCuenta(cuenta: cuenta), ancho, escala);
          expect(tester.takeException(), isNull);
          for (final r in ['Comprado', 'Entregado', 'Pagado', 'Saldo']) {
            _sinPartir(tester, r, escala, unRenglon: false);
          }
        });
      }
    }
  });

  group('TarjetaDeDatos (devolución 31): rótulo y valor, toda la escala', () {
    final datos = [
      const DatoDeDevolucion('Se queda con', '\$ 123.456,50'),
      const DatoDeDevolucion('Ya pagó', '\$ 4.500'),
      const DatoDeDevolucion('Saldo nuevo', '\$ 21.474.836,47', fuerte: true),
    ];
    for (final ancho in anchos) {
      for (final escala in escalas) {
        testWidgets('${ancho.toInt()} dp × $escala', (tester) async {
          await _cargarFuentes(tester);
          await _montar(tester, TarjetaDeDatos(datos: datos), ancho, escala);
          expect(tester.takeException(), isNull);
          for (final d in datos) {
            _sinPartir(tester, d.rotulo, escala, unRenglon: false);
            // El valor (con espacio sin quiebre) nunca se parte en dos renglones.
            final finder = find.text(d.valor);
            expect(finder, findsOneWidget);
            final p = tester.renderObject<RenderParagraph>(finder);
            final estilo = TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: d.fuerte ? 16 : 14,
              fontWeight: d.fuerte ? FontWeight.w600 : FontWeight.w400,
            );
            expect(
              p.size.width + 0.5,
              greaterThanOrEqualTo(_ancho(d.valor, estilo, escala)),
              reason: '«${d.valor}» a ×$escala (${ancho.toInt()} dp) se partió en dos renglones',
            );
          }
        });
      }
    }
  });
}
