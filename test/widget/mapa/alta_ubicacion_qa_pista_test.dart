// QA de #286 / PR #288 (vista 03 sobre MapaBase): la pista «Mové el mapa para ajustar el punto» y el
// pin en el mapa chico (360×640) con el texto agrandado, medidos con las fuentes reales.
//
// Los hallazgos de QA quedan con `skip: true` y el motivo en un comentario `// skip: QA #286 …`; el
// implementador les saca el `skip` cuando los arregla.
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart';

/// La pastilla oscura entera de la pista [texto] (no solo su texto).
Finder _pastilla(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.byType(Container)).first;

Finder get _pastillaPista => _pastilla(TextosAlta.mover);

Finder get _botonVolver => find.byTooltip(TextosAlta.volverAMiUbicacion);

void _sinSolape(WidgetTester tester, Finder a, Finder b, String que) {
  final ra = tester.getRect(a);
  final rb = tester.getRect(b);
  expect(ra.overlaps(rb), isFalse, reason: '$que: $ra se pisa con $rb');
}

void main() {
  setUpAll(cargarFuentesReales);

  group('QA #286 · vista 03 A·01 · la pista no tapa el pin en el mapa chico', () {
    testWidgets('a 360×640 y texto 1x la pista no pisa el pin', (tester) async {
      await montarAlta(tester, tamano: const Size(360, 640));
      await tester.pumpAndSettle();

      _sinSolape(tester, _pastillaPista, find.byType(PinAlta), 'pista vs pin');
    });

    testWidgets('a 360×640 y texto 1.3x la pista no pisa el pin', (tester) async {
      await montarAlta(tester, tamano: const Size(360, 640), escala: 1.3);
      await tester.pumpAndSettle();

      _sinSolape(tester, _pastillaPista, find.byType(PinAlta), 'pista vs pin');
    });

    testWidgets('a 360×640 y texto 2x la pista deja margen a los bordes y no pisa el pin', (
      tester,
    ) async {
      await montarAlta(tester, tamano: const Size(360, 640), escala: 2);
      await tester.pumpAndSettle();

      final pastilla = tester.getRect(_pastillaPista);
      expect(pastilla.left, greaterThanOrEqualTo(8), reason: 'la pista toca el borde: $pastilla');
      expect(pastilla.right, lessThanOrEqualTo(352), reason: 'la pista toca el borde: $pastilla');
      _sinSolape(tester, _pastillaPista, find.byType(PinAlta), 'pista vs pin');
    });
  });

  group('#288 · la pista queda debajo de la punta del pin y deja libre el botón', () {
    for (final escala in [1.0, 1.3, 2.0]) {
      testWidgets(
        'a 360×640 y texto ${escala}x entra en el mapa, bajo la punta, sin tocar el botón',
        (tester) async {
          await montarAlta(tester, tamano: const Size(360, 640), escala: escala);
          await tester.pumpAndSettle();

          final mapa = tester.getRect(find.byType(MapaAlta));
          final pastilla = tester.getRect(_pastillaPista);
          final punta = tester.getRect(find.byType(PinAlta)).bottom;

          expect(_botonVolver, findsOneWidget, reason: 'con lectura de GPS hay botón');
          expect(pastilla.top, greaterThanOrEqualTo(punta), reason: 'no tapa la punta del pin');
          expect(pastilla.bottom, lessThanOrEqualTo(mapa.bottom), reason: 'se sale del mapa');
          expect(pastilla.left, greaterThanOrEqualTo(16), reason: 'sin margen: $pastilla');
          expect(
            pastilla.width,
            lessThan(mapa.width - 32),
            reason: 'ocupa todo el ancho: $pastilla',
          );
          _sinSolape(tester, _pastillaPista, _botonVolver, 'pista vs «Volver a mi ubicación»');
          _sinSolape(tester, _pastillaPista, find.byType(PinAlta), 'pista vs pin');
          // El texto es el de siempre.
          expect(find.text(TextosAlta.mover), findsOneWidget);
        },
      );
    }

    testWidgets('sin ubicación del GPS (sin botón) «Tocá el mapa…» usa el ancho, con margen', (
      tester,
    ) async {
      await montarAlta(tester, tamano: const Size(360, 640), escala: 2, gps: gpsSinPermiso);
      await tester.pumpAndSettle();

      final pastilla = tester.getRect(_pastilla(TextosAlta.tocar));
      expect(_botonVolver, findsNothing);
      expect(pastilla.left, greaterThanOrEqualTo(16));
      expect(pastilla.right, lessThanOrEqualTo(344));
      expect(pastilla.top, greaterThanOrEqualTo(tester.getRect(find.byType(PinAlta)).bottom));
      expect(pastilla.bottom, lessThanOrEqualTo(tester.getRect(find.byType(MapaAlta)).bottom));
    });

    testWidgets('en el teléfono de siempre (390×844) la pista sigue centrada', (tester) async {
      await montarAlta(tester, gps: gpsSinPermiso);
      await tester.pumpAndSettle();

      expect(tester.getRect(_pastilla(TextosAlta.tocar)).center.dx, closeTo(195, 0.5));
    });
  });

  group('#288 · la atribución «© OpenStreetMap» en el mapa chico con el texto agrandado', () {
    const texto = '© OpenStreetMap';
    const fuente = FuenteMapa.offline('/data/uy.pmtiles');

    for (final escala in [1.0, 2.0]) {
      testWidgets('a 360×640 y texto ${escala}x se lee entera, dentro del mapa y sin pisar nada', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await montarAlta(tester, tamano: const Size(360, 640), escala: escala, fuente: fuente);
        await tester.pumpAndSettle();

        final mapa = tester.getRect(find.byType(MapaAlta));
        final atribucion = tester.getRect(find.text(texto));
        // Escala con el texto: una línea mide 12 dp × la escala.
        expect(atribucion.height, greaterThanOrEqualTo(12 * escala - 0.5));
        expect(tester.widget<Text>(find.text(texto)).overflow, isNull);
        expect(atribucion.left, greaterThanOrEqualTo(mapa.left));
        expect(atribucion.bottom, lessThanOrEqualTo(mapa.bottom), reason: 'la tapa la hoja');
        expect(atribucion.top, greaterThanOrEqualTo(mapa.top));
        _sinSolape(tester, find.text(texto), _botonVolver, 'atribución vs «Volver a mi ubicación»');
        _sinSolape(tester, find.text(texto), find.byType(PinAlta), 'atribución vs pin');
        _sinSolape(tester, find.text(texto), _pastillaPista, 'atribución vs pista');
        expect(find.bySemanticsLabel(texto), findsOneWidget, reason: 'TalkBack la lee');
        semantica.dispose();
      });
    }

    testWidgets('sin tiles no hay atribución', (tester) async {
      await montarAlta(tester, tamano: const Size(360, 640), escala: 2);
      await tester.pumpAndSettle();

      expect(find.text(texto), findsNothing);
    });
  });
}
