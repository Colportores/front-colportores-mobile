// El chip del GPS y la pista del alta (vista 03) con el teclado abierto y la barra de estado de 24 dp
// (comentario 6026772473 del #199): ni el chip «GPS ±N m» ni la pista pueden quedar sobre la punta
// del pin. Medidas con las fuentes reales del proyecto.
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart';

/// La barra de estado de un Android común.
const _barraDeEstado = 24.0;

Future<void> _montar(WidgetTester tester, {double escala = 1, GpsFalso? gps}) async {
  tester.view.padding = const FakeViewPadding(top: _barraDeEstado);
  tester.view.viewPadding = const FakeViewPadding(top: _barraDeEstado);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  await montarAlta(tester, tamano: const Size(360, 640), escala: escala, gps: gps);
  await tester.pumpAndSettle();
}

Future<void> _abrirTeclado(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pumpAndSettle();
}

Future<void> _cerrarTeclado(WidgetTester tester) async {
  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
}

Finder get _chipGps => find.textContaining('GPS');

Finder get _textoPista => find.byWidgetPredicate(
  (w) => w is Text && (w.data == TextosAlta.mover || w.data == TextosAlta.tocar),
);

/// La punta del pin: el centro del mapa, abajo del pin.
Offset _punta(WidgetTester tester) {
  final pin = tester.getRect(find.byType(PinAlta));
  return Offset(pin.center.dx, pin.bottom);
}

/// Los textos que están dentro del mapa y cubren la punta del pin (con 4 dp de aire alrededor).
List<String> _textosSobreLaPunta(WidgetTester tester) {
  final mapa = tester.getRect(find.byType(MapaAlta));
  final zona = Rect.fromCenter(center: _punta(tester), width: 8, height: 8);
  final cubren = <String>[];
  for (final elemento in find.byType(Text).evaluate()) {
    final caja = elemento.renderObject;
    if (caja is! RenderBox || !caja.attached || !caja.hasSize) continue;
    final rect = caja.localToGlobal(Offset.zero) & caja.size;
    if (rect.top < mapa.bottom && rect.overlaps(zona)) {
      cubren.add((elemento.widget as Text).data ?? '');
    }
  }
  return cubren;
}

void main() {
  setUpAll(cargarFuentesReales);

  group('Alta · chip del GPS y pista con el teclado abierto y 24 dp de barra de estado', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'a 360×640 y texto ${escala}x: con el teclado abierto no hay chip ni pista, y el pin queda '
        'libre; al cerrarlo, los dos vuelven',
        (tester) async {
          await _montar(tester, escala: escala);
          // Control: sin teclado el chip y la pista están, y el chip baja por la barra de estado.
          expect(_chipGps, findsOneWidget);
          expect(_textoPista, findsOneWidget);
          expect(tester.getTopLeft(_chipGps).dy, greaterThanOrEqualTo(_barraDeEstado + 14));
          final altoSinTeclado = tester.getSize(find.byType(MapaAlta)).height;

          await _abrirTeclado(tester);

          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(MapaAlta)).height,
            lessThan(altoSinTeclado - 100),
            reason: 'el teclado achica el mapa',
          );
          expect(_chipGps, findsNothing, reason: 'el chip no se muestra con el teclado abierto');
          expect(_textoPista, findsNothing, reason: 'la pista tampoco');
          expect(find.byType(PinAlta), findsOneWidget);
          final mapa = tester.getRect(find.byType(MapaAlta));
          final pin = tester.getRect(find.byType(PinAlta));
          expect(mapa.contains(pin.bottomCenter), isTrue, reason: 'el pin sigue a la vista');
          expect(
            _textosSobreLaPunta(tester),
            isEmpty,
            reason: 'nada tapa la punta del pin con el teclado abierto',
          );
          // Lo que sigue a la vista: «Cerrar» y «Volver a mi ubicación».
          expect(find.byTooltip(TextosAlta.cerrar), findsOneWidget);
          expect(find.byTooltip(TextosAlta.volverAMiUbicacion), findsOneWidget);

          await _cerrarTeclado(tester);

          expect(_chipGps, findsOneWidget, reason: 'sin teclado el chip vuelve');
          expect(_textoPista, findsOneWidget, reason: 'y la pista también');
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'sin GPS a 360×640 y texto ${escala}x: con el teclado abierto tampoco hay «Sin GPS» sobre '
        'el pin',
        (tester) async {
          await _montar(tester, escala: escala, gps: gpsSinPermiso);
          expect(find.text('Sin GPS'), findsOneWidget);

          await _abrirTeclado(tester);

          expect(find.text('Sin GPS'), findsNothing);
          expect(_textosSobreLaPunta(tester), isEmpty);
          expect(find.byTooltip(TextosAlta.volverAMiUbicacion), findsNothing);

          await _cerrarTeclado(tester);

          expect(find.text('Sin GPS'), findsOneWidget);
        },
      );
    }

    testWidgets('abrir y cerrar el teclado seguido no deja el chip ni la pista a medias', (
      tester,
    ) async {
      await _montar(tester);

      for (var i = 0; i < 3; i++) {
        await _abrirTeclado(tester);
        expect(_chipGps, findsNothing);
        await _cerrarTeclado(tester);
        expect(_chipGps, findsOneWidget);
        expect(_textoPista, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
