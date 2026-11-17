// QA de #718 (P2 §2 del QA de #715): el `switchTheme` global lleva el borde y el pulgar del interruptor
// apagado a 3:1 o más (WCAG 1.4.11) en TODOS los interruptores de la app, incluido el de «Mostrar
// bajas» de la hoja de filtros de la Lista (la decisión nombra «filtros de la Lista»). Se mide en
// píxeles, con el interruptor dibujado de verdad: el primer color distinto del fondo, yendo de
// izquierda a derecha por el centro del componente, es su borde visible.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_fuera_del_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_mapa_fuera_del_area_715_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

double _luz(Color c) {
  double canal(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * canal(c.r) + .7152 * canal(c.g) + .0722 * canal(c.b);
}

double _contraste(Color a, Color b) {
  final la = _luz(a);
  final lb = _luz(b);
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

/// El borde visible del interruptor [f] y su fondo, medidos sobre los píxeles de la pantalla.
Future<({Color fondo, Color borde, Color pulgar, Color pista})> _medir(
  WidgetTester tester,
  Finder f,
) async {
  await tester.pump(const Duration(milliseconds: 500));
  final caja = tester.getRect(f);
  final datos = await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return (bytes: bytes, ancho: img.width);
  });
  final bytes = datos!.bytes;
  final ancho = datos.ancho;
  Color px(num x, num y) {
    final i = ((y.round() * ancho) + x.round()) * 4;
    return Color.fromARGB(
      bytes.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
  }

  bool distinto(Color a, Color b) =>
      ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 > 18;

  final y = caja.center.dy;
  final fondo = px(caja.left + 1, y);
  var x = caja.left + 1;
  while (x < caja.right && !distinto(px(x, y), fondo)) {
    x++;
  }
  final borde = px(x + 1, y);
  // El pulgar apagado está a la izquierda: su centro queda ~16 dp adentro de la pista de 52 dp.
  final pulgar = px(x + 16, y);
  final pista = px(x + 38, y);
  return (fondo: fondo, borde: borde, pulgar: pulgar, pista: pista);
}

Future<void> _montarSuelto(WidgetTester tester, {required Color fondo, bool valor = false}) async {
  tester.view.physicalSize = const Size(390, 300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      home: Scaffold(
        backgroundColor: fondo,
        body: Center(
          child: Switch(key: const Key('s'), value: valor, onChanged: (_) {}),
        ),
      ),
    ),
  );
}

void main() {
  group('QA #718 · un interruptor de la app, apagado y encendido, medido en píxeles', () {
    for (final (nombre, fondo) in [
      ('blanco de la hoja', Colors.white),
      ('crema de la pantalla', const Color(0xFFFAFAF7)),
    ]) {
      testWidgets('apagado sobre el $nombre: el borde y el pulgar a 3:1 o más', (tester) async {
        await _montarSuelto(tester, fondo: fondo);
        final m = await _medir(tester, find.byKey(const Key('s')));

        expect(_contraste(m.borde, m.fondo), greaterThanOrEqualTo(3), reason: 'borde ${m.borde}');
        expect(_contraste(m.pulgar, m.fondo), greaterThanOrEqualTo(3), reason: 'pulgar ${m.pulgar}');
        // El pulgar se distingue de su pista (la forma del estado: pulgar a la izquierda).
        expect(
          _contraste(m.pulgar, m.pista),
          greaterThanOrEqualTo(3),
          reason: 'pulgar sobre pista',
        );
      });

      testWidgets('encendido sobre el $nombre: la pista a 3:1 o más (no cambió)', (tester) async {
        await _montarSuelto(tester, fondo: fondo, valor: true);
        final m = await _medir(tester, find.byKey(const Key('s')));

        expect(_contraste(m.borde, m.fondo), greaterThanOrEqualTo(3), reason: 'pista ${m.borde}');
      });
    }
  });

  group('QA #718 · los interruptores reales de la app', () {
    testWidgets('«Mostrar las casas fuera de tu área» de «Referencias», apagado: borde y pulgar a '
        '3:1 o más', (tester) async {
      await montar715(tester, FueraDelAreaFalsas715({'u1', 'u3'}));
      await abrirReferencias715(tester);
      await tester.ensureVisible(interruptor715);
      await tester.tap(interruptor715);
      await asentarLista(tester, 4);
      expect(tester.widget<SwitchListTile>(interruptor715).value, isFalse);

      final m = await _medir(
        tester,
        find.descendant(
          of: find.byKey(ClavesFueraDelArea.interruptor),
          matching: find.byType(Switch),
        ),
      );
      expect(_contraste(m.borde, m.fondo), greaterThanOrEqualTo(3), reason: 'borde ${m.borde}');
      expect(_contraste(m.pulgar, m.fondo), greaterThanOrEqualTo(3), reason: 'pulgar ${m.pulgar}');
    });

    testWidgets('«Mostrar bajas» de la hoja de filtros de la Lista, apagado: el borde y el pulgar '
        'a 3:1 o más (la decisión del 17/11 nombra «filtros de la Lista»)', (tester) async {
      await montarLista(tester, repo: RepoListaFalso([filaLista('u1')]));
      await abrirHojaFiltros(tester);
      await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
      await asentarLista(tester, 4);

      final m = await _medir(
        tester,
        find.descendant(
          of: find.byKey(const Key('hoja_filtros_bajas')),
          matching: find.byType(Switch),
        ),
      );
      expect(_contraste(m.borde, m.fondo), greaterThanOrEqualTo(3), reason: 'borde ${m.borde}');
      expect(_contraste(m.pulgar, m.fondo), greaterThanOrEqualTo(3), reason: 'pulgar ${m.pulgar}');
    });
  });
}
