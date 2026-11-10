// QA de la pregunta «¿María no te pagó?» (decisión de Cristian, 03/11, y salir del cobro del 10/11, #440):
// lo que no cubren los tests del PR. Los cinco estados del diálogo × 360×640 y 412×915 × texto 1,0 y
// 2,0 (sin desborde, sin texto cortado, con los dos botones a la vista y captura), con el teclado
// abierto, el teléfono acostado y el «¿Descartar lo que escribiste?» que antecede a la pregunta cuando
// se sale del cobro con algo escrito.
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`).
import 'dart:ui' show Size;

import 'package:colportores_mobile/features/cobranzas/presentation/widgets/dialogo_no_te_pago.dart';
import 'package:flutter/widgets.dart' show Offset, Scrollable;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cobrar_desde_la_casa_arnes.dart';
import '../../helpers/cobro_arnes.dart';
import '../../helpers/pregunta_al_cancelar_440_arnes.dart';
import '../../helpers/qa_vista23_408_arnes.dart' show cargarFuentes408;
import '../../helpers/qa_vista39_440_arnes.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// Se llega a los dos botones de la pregunta (desplazando el diálogo si hace falta) y quedan sobre
/// [bajoElPliegue].
Future<void> _llegarALosBotones(WidgetTester tester, double bajoElPliegue) async {
  for (final k in [ClavesNoTePago.anotar, ClavesNoTePago.noMeEquivoque]) {
    final f = find.byKey(k);
    await tester.ensureVisible(f);
    await tester.pump();
    final r = tester.getRect(f);
    expect(r.top, greaterThanOrEqualTo(0), reason: '$k arriba de la pantalla');
    expect(r.bottom, lessThanOrEqualTo(bajoElPliegue + 0.5), reason: '$k bajo el pliegue');
  }
}

void main() {
  group('Los cinco estados de la pregunta: sin desborde, sin texto cortado, con captura', () {
    for (final tamano in [chico440, grande440]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in EstadoPregunta440.values) {
          testWidgets('${estado.rotulo} · ${sufijo440(tamano, escala)}', (tester) async {
            final agenda = await llegarAPregunta440(tester, estado, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull);
            sinTextoCortado440(tester);
            await capturar440(tester, 'pregunta_${estado.name}_${sufijo440(tamano, escala)}');
            await _llegarALosBotones(tester, tamano.height);
            await liberarPregunta440(tester, agenda);
          });
        }
      }
    }
  });

  group('Teclado abierto y teléfono acostado', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'con el teclado arriba (280 px) en 360×640 · x$escala: los dos botones se alcanzan',
        (tester) async {
          final agenda = await llegarAPregunta440(
            tester,
            EstadoPregunta440.nombreLargo,
            tamano: chico440,
            escala: escala,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await asentarAgendar(tester);

          expect(tester.takeException(), isNull);
          sinTextoCortado440(tester);
          await capturar440(tester, 'pregunta_teclado_x$escala');
          await _llegarALosBotones(tester, chico440.height - 280);
          await liberarPregunta440(tester, agenda);
        },
      );

      testWidgets('acostado (640×360) · x$escala: sin desborde y los dos botones se alcanzan', (
        tester,
      ) async {
        final agenda = await llegarAPregunta440(
          tester,
          EstadoPregunta440.falla,
          tamano: const Size(640, 360),
          escala: escala,
        );

        expect(tester.takeException(), isNull);
        sinTextoCortado440(tester);
        await capturar440(tester, 'pregunta_acostado_x$escala');
        await _llegarALosBotones(tester, 360);
        await liberarPregunta440(tester, agenda);
      });
    }
  });

  group('Salir del cobro con algo escrito: «¿Descartar lo que escribiste?» antes de la pregunta', () {
    for (final tamano in [chico440, grande440]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('${sufijo440(tamano, escala)}: el aviso entra y se leen sus dos salidas', (
          tester,
        ) async {
          await cargarFuentes408(tester);
          await montarCobrarDesdeLaCasa(
            tester,
            repo: cobranzasConVentas([ventaDelCanvas38()]),
            escala: escala,
            tamano: tamano,
          );
          await capturar440(tester, 'cobro_${sufijo440(tamano, escala)}');
          await escribirMonto(tester, '600');
          // La «✕» va en la cabecera de la lista, no fija: tras escribir el monto hay que subir a ella.
          await tester.drag(
            find.descendant(of: pagina, matching: find.byType(Scrollable)).first,
            const Offset(0, 2000),
          );
          await tester.pump();
          await tocarCobro(tester, cerrarCobro);

          expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
          expect(find.text('Descartar'), findsOneWidget);
          expect(find.text('Seguir escribiendo'), findsOneWidget);
          expect(tester.takeException(), isNull);
          sinTextoCortado440(tester);
          await capturar440(tester, 'descartar_${sufijo440(tamano, escala)}');
          for (final t in ['Descartar', 'Seguir escribiendo']) {
            await tester.ensureVisible(find.text(t));
            await tester.pump();
            final r = tester.getRect(find.text(t));
            expect(
              r.bottom,
              lessThanOrEqualTo(tamano.height + 0.5),
              reason: '«$t» bajo el pliegue',
            );
          }
        });
      }
    }
  });
  group('Hallazgos (con skip; `--dart-define=QA_HALLAZGOS=true` los corre)', () {
    testWidgets(
      'QA #440: la «✕» del cobro, que ahora es el «Cancelar», sigue a la vista después de escribir el '
      'monto (360×640, texto al 200 %): va en la cabecera de la lista y sale de la pantalla; atrás sí sirve',
      (tester) async {
        await cargarFuentes408(tester);
        await montarCobrarDesdeLaCasa(
          tester,
          repo: cobranzasConVentas([ventaDelCanvas38()]),
          escala: 2,
          tamano: chico440,
        );
        await escribirMonto(tester, '600');

        expect(cerrarCobro.hitTestable(), findsOneWidget);
      },
      skip: !_verHallazgos,
    );
  });
}
