// QA #429: capturas PNG de la ficha con «Entregar» (solo con `--dart-define=QA_CAPTURAS=true`; las
// deja en `.dart_tool/qa_capturas/`, que no se commitea). Sin eso el archivo no registra tests.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

Future<void> _fuentes(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await c.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final c = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(bytes.buffer)));
        await c.load();
        break;
      }
    }
  });
}

Future<void> _captura(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/429_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  if (!_conCapturas) return;

  EntregaEnFicha pendiente(String id, String ventaId, String producto) => EntregaEnFicha(
    id: id,
    fecha: DateTime(2026, 10, 24, 12),
    pendiente: true,
    ventaId: ventaId,
    lineas: [LineaDeFicha(nombre: producto, cantidad: 1)],
  );

  MundoFicha mundo({bool baja = false}) {
    final m = MundoFicha(
      persona: baja ? mariaDePrueba(baja: DateTime(2026, 10, 22)) : null,
      historial: [
        pendiente('p1', 'ven-1', 'Nuestros Hijos'),
        CobroEnFicha(
          id: 'cob-1',
          fecha: DateTime(2026, 10, 20, 12),
          montoCentavos: 60000,
          efectivo: true,
          ventaId: 'ven-1',
          numeroTalonario: '0042',
        ),
        ...historialDelCanvas(),
      ],
      notasIniciales: notasDeLaFicha(),
      contexto: baja ? contextoBajaDesde22() : null,
    )..conRegistrarEntrega = true;
    m.cuentas.cuenta = cuentaConSaldo;
    return m;
  }

  final configs = <(String, Size, double)>[
    ('360x640_1x', const Size(360, 640), 1),
    ('360x640_2x', const Size(360, 640), 2),
    ('412x915_1x', const Size(412, 915), 1),
    ('412x915_2x', const Size(412, 915), 2),
  ];

  for (final (n, tam, esc) in configs) {
    testWidgets('captura ficha con pendiente $n', (tester) async {
      await _fuentes(tester);
      await montarFicha(tester, mundo(), tamano: tam, escala: esc);
      await tester.dragUntilVisible(
        find.byKey(ClavesFicha.fila('p1')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.ensureVisible(find.byKey(ClavesFicha.fila('p1')));
      await tester.pump(const Duration(milliseconds: 200));
      await _captura(tester, 'pendiente_$n');
    });

    testWidgets('captura filtro Entrega pendiente $n', (tester) async {
      await _fuentes(tester);
      await montarFicha(tester, mundo(), tamano: tam, escala: esc);
      final chip = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente));
      await tester.dragUntilVisible(chip, find.byType(Scrollable).first, const Offset(0, -200));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await asentar(tester);
      await tester.ensureVisible(find.byKey(ClavesFicha.fila('p1')));
      await tester.pump(const Duration(milliseconds: 200));
      await _captura(tester, 'filtro_$n');
    });

    testWidgets('captura persona de baja $n', (tester) async {
      await _fuentes(tester);
      await montarFicha(tester, mundo(baja: true), tamano: tam, escala: esc);
      await tester.dragUntilVisible(
        find.byKey(ClavesFicha.fila('p1')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.ensureVisible(find.byKey(ClavesFicha.fila('p1')));
      await tester.pump(const Duration(milliseconds: 200));
      await _captura(tester, 'baja_$n');
    });
  }
}
