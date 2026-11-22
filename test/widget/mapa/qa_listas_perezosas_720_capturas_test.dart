// QA #720 (PR #721): capturas PNG de «Entregas pendientes» y «Ver borradas» (persona y lugar) con 60
// registros, solo con `--dart-define=QA_CAPTURAS=true`. Van a `.dart_tool/qa_capturas/` (fuera del
// repo) para mirarlas; los tests no afirman nada de ellas.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/nota_persona_falsos.dart';
import '../../helpers/nota_ubicacion_falsos.dart';
import '../../helpers/qa_agenda_148_arnes.dart' show cargarFuentes;
import 'notas_lugar_arnes.dart';
import 'notas_persona_arnes.dart';

const _capturas = bool.fromEnvironment('QA_CAPTURAS');

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = RendererBinding.instance.renderViews.first.debugLayer! as OffsetLayer;
    final vista = tester.view;
    final img = await capa.toImage(Offset.zero & (vista.physicalSize / vista.devicePixelRatio));
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/720_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> _saltar(WidgetTester tester, Finder scroll, double fraccion) async {
  final s = tester.state<ScrollableState>(
    find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
  );
  s.position.jumpTo(s.position.maxScrollExtent * fraccion);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final (nombre, tam, escala) in [
    ('360x640_x1', const Size(360, 640), 1.0),
    ('360x640_x2', const Size(360, 640), 2.0),
    ('412x915_x1', const Size(412, 915), 1.0),
  ]) {
    testWidgets('entregas $nombre', (tester) async {
      await cargarFuentes(tester);
      final e = EntornoDeEntrega();
      e.entregas.emitirPendientes([
        for (var i = 0; i < 60; i++)
          pendienteDe(
            'v-$i',
            fecha: i < 20
                ? DateTime(2026, 10, 1 + i, 10)
                : i < 40
                ? DateTime(2026, 11, 1 + i - 20, 9)
                : null,
            vinculo: 'ep-${1 + i % 3}',
            lineas: [lineaDe('e-$i', 'p-hijos', 1 + i % 4)],
          ),
      ]);
      await montarPantalla(
        tester,
        e,
        () => EntregasPendientesPage.ruta(colportorId: 'col-1'),
        tamano: tam,
        escala: escala,
      );
      final lista = find.byKey(const Key('entregas_lista'));
      await _foto(tester, 'entregas_${nombre}_arriba');
      await _saltar(tester, lista, 0.5);
      await _foto(tester, 'entregas_${nombre}_medio');
      await _saltar(tester, lista, 1);
      await _foto(tester, 'entregas_${nombre}_fondo');
    }, skip: !_capturas);

    testWidgets('borradas persona $nombre', (tester) async {
      await cargarFuentes(tester);
      final repo = NotaPersonaRepositorioFalso(
        notas: [
          for (var i = 0; i < 60; i++)
            notaDePrueba(
              'b-$i',
              'Nota borrada número $i: pidió volver el sábado con el esposo.',
              creada: DateTime(2026, 10, 21).subtract(Duration(days: i % 80)),
              borrada: DateTime(2026, 10, 21, 10).subtract(Duration(days: i % 80)),
            ),
        ],
      );
      await montarNotas(tester, repo: repo, escala: escala, tamano: tam);
      await tester.scrollUntilVisible(
        find.text('Ver borradas (60)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Ver borradas (60)'));
      await asentar(tester);
      await _foto(tester, 'borradas_persona_${nombre}_arriba');
      await _saltar(tester, find.byType(Scaffold).last, 1);
      await _foto(tester, 'borradas_persona_${nombre}_fondo');
    }, skip: !_capturas);

    testWidgets('borradas lugar $nombre', (tester) async {
      await cargarFuentes(tester);
      final repo = NotaUbicacionRepositorioFalso(
        notas: [
          for (var i = 0; i < 60; i++)
            notaDeLugar(
              'b-$i',
              'Nota del lugar $i: el portón verde no cierra, tocar fuerte.',
              creada: DateTime(2026, 10, 21).subtract(Duration(days: i % 80)),
              borrada: DateTime(2026, 10, 21, 10).subtract(Duration(days: i % 80)),
            ),
        ],
      );
      await montarPestanaLugar(tester, repo: repo, escala: escala, tamano: tam);
      await tester.tap(find.textContaining('Ver borradas'));
      await asentarLugar(tester);
      await _foto(tester, 'borradas_lugar_${nombre}_arriba');
      await _saltar(tester, find.byType(Scaffold).last, 1);
      await _foto(tester, 'borradas_lugar_${nombre}_fondo');
    }, skip: !_capturas);
  }
}
