// QA de la vista 30 B (#168): cada estado (los 8 artboards y los que el canvas no dibuja) en 360x640 y
// 412x915 con texto 1,0 y 2,0: se llega, no hay overflow ni texto cortado y nada queda sin contenido.
// Con `--dart-define=QA_CAPTURAS=true` deja una captura de cada uno en `.dart_tool/qa_capturas`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/anular_cobro_arnes.dart';
import '../../helpers/qa_anular_cobro_168_arnes.dart';

void main() {
  for (final tamano in const [chico168, grande168]) {
    for (final escala in const [1.0, 2.0]) {
      for (final estado in Estado168.values) {
        testWidgets('${estado.rotulo} · ${sufijo168(tamano, escala)}', (tester) async {
          final repo = await llegarA168(tester, estado, tamano, escala);
          expect(tester.takeException(), isNull, reason: 'overflow o error al dibujar');
          sinTextoCortado168(tester);
          await capturar168(tester, '${estado.archivo}_${sufijo168(tamano, escala)}');
          // Todo estado tiene contenido: algún texto además del encabezado (cargando es el esqueleto,
          // con su etiqueta para el lector de pantalla).
          if (estado == Estado168.cargando) {
            expect(find.byKey(const Key('cobro_cargando')), findsOneWidget);
          } else {
            expect(find.byType(Text).evaluate().length, greaterThan(2));
          }
          // Sin spinner a secas: si hay progreso, hay un texto o una etiqueta que dice qué espera.
          if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
            expect(find.text('Anulando…'), findsOneWidget);
          }
          await liberar168(tester, repo);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  group('Los botones de la pantalla se alcanzan con texto 2,0 a 360x640', () {
    testWidgets('detalle: «Anular cobro» queda dentro de la pantalla', (tester) async {
      await llegarA168(tester, Estado168.c01Detalle, chico168, 2);
      final r = tester.getRect(botonAnularDelDetalle);
      expect(r.bottom, lessThanOrEqualTo(640));
      expect(r.top, greaterThanOrEqualTo(0));
    });

    testWidgets('anular: el botón principal queda dentro de la pantalla con el aviso de error', (
      tester,
    ) async {
      await llegarA168(tester, Estado168.c08Error, chico168, 2);
      final r = tester.getRect(botonPrincipal);
      expect(r.bottom, lessThanOrEqualTo(640));
      expect(r.height, greaterThanOrEqualTo(48));
    });
  });
}
