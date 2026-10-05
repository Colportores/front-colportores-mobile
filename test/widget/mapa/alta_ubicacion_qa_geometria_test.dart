// QA de las vistas 03 y 04 (#193): medidas de texto y de solapes con las fuentes reales del proyecto.
//
// Con la fuente de prueba de `flutter_test` (Ahem) cada letra mide un cuadrado y los avisos que
// flotan sobre el mapa parecen más grandes de lo que son, así que acá se cargan Inter, Source Serif 4
// y JetBrains Mono. El contraste (`textContrastGuideline`) no se prueba acá: con texto antialiasado
// da falsos negativos en letra chica; está en `alta_ubicacion_qa_test.dart`.
//
// Los tests con `skip` documentan un hallazgo de QA: el implementador les saca el `skip` cuando lo
// arregla.
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_duplicado_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart';

/// El recuadro blanco de «Sin tiles para esta zona…» que flota abajo a la izquierda del mapa.
Finder get _avisoSinTiles => find.byWidgetPredicate(
  (w) => w is Container && w.child is Text && (w.child as Text).data == TextosAlta.sinTiles,
);

/// El botón «Activar GPS» entero (con su área de toque), no solo su texto.
Finder get _botonActivarGps =>
    find.ancestor(of: find.text('Activar GPS'), matching: find.byType(TextButton)).first;

/// Los rectángulos de [a] y [b] no se pisan.
void _sinSolape(WidgetTester tester, Finder a, Finder b, String que) {
  final ra = tester.getRect(a);
  final rb = tester.getRect(b);
  expect(ra.overlaps(rb), isFalse, reason: '$que: $ra se pisa con $rb');
}

void main() {
  setUpAll(cargarFuentesReales);

  group('QA #193 · vista 03 · avisos sobre el mapa en el tamaño chico (360×640)', () {
    // skip: QA #193 — el aviso «Sin tiles…» (siempre activo hasta que haya adaptador de tiles) tapa el
    // botón «Activar GPS» del aviso de sin GPS: parte del botón queda debajo del recuadro blanco.
    testWidgets('sin GPS, el aviso «Sin tiles…» no tapa el botón «Activar GPS»', (tester) async {
      await montarAlta(tester, gps: gpsSinPermiso, tamano: const Size(360, 640));

      _sinSolape(tester, _avisoSinTiles, _botonActivarGps, 'sin tiles vs «Activar GPS»');
    }, skip: true);

    // skip: QA #193 — a texto 2x el aviso «Sin tiles…» (4 renglones) se monta sobre la pista del pin, el
    // pin y «Volver a mi ubicación»: con el mapa chico, el pin queda tapado.
    testWidgets(
      'con GPS y texto 2x, el aviso «Sin tiles…» no tapa el pin, la pista ni «Volver a mi ubicación»',
      (tester) async {
        await montarAlta(tester, tamano: const Size(360, 640), escala: 2);

        _sinSolape(tester, _avisoSinTiles, find.byType(PinAlta), 'sin tiles vs pin');
        _sinSolape(tester, _avisoSinTiles, find.text(TextosAlta.mover), 'sin tiles vs pista');
        _sinSolape(
          tester,
          _avisoSinTiles,
          find.byTooltip('Volver a mi ubicación'),
          'sin tiles vs «Volver a mi ubicación»',
        );
      },
      skip: true,
    );

    testWidgets('a 412×915 el aviso «Sin tiles…» no se pisa con nada', (tester) async {
      await montarAlta(tester, gps: gpsSinPermiso, tamano: const Size(412, 915));

      _sinSolape(tester, _avisoSinTiles, _botonActivarGps, 'sin tiles vs «Activar GPS»');
      _sinSolape(tester, _avisoSinTiles, find.text(TextosAlta.tocar), 'sin tiles vs pista');
    });

    for (final tamano in [const Size(360, 640), const Size(412, 915)]) {
      testWidgets('con las fuentes reales cumple los tamaños de toque en '
          '${tamano.width.toInt()}×${tamano.height.toInt()}', (tester) async {
        final handle = tester.ensureSemantics();
        await montarAlta(tester, tamano: tamano);

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }
  });

  group('QA #193 · vista 04 · paso de justificación (B·03) con las fuentes reales', () {
    // skip: QA #193 — a texto 2x los motivos sugeridos se cortan («Otra puerta en el mism…»): el
    // `ActionChip` no parte el texto en renglones y lo desvanece en vez de mostrarlo entero.
    testWidgets('a texto 2x cada motivo sugerido se lee completo, sin cortarse', (tester) async {
      await hastaJustificacion(tester, escala: 2, tamano: const Size(360, 640));

      for (final motivo in TextosDuplicado.motivos) {
        final parrafo = tester.renderObject<RenderParagraph>(find.text(motivo));
        expect(parrafo.debugHasOverflowShader, isFalse, reason: '«$motivo» se corta');
      }
    }, skip: true);

    testWidgets('a texto 1x los motivos sugeridos se leen completos', (tester) async {
      await hastaJustificacion(tester, tamano: const Size(360, 640));

      for (final motivo in TextosDuplicado.motivos) {
        final parrafo = tester.renderObject<RenderParagraph>(find.text(motivo));
        expect(parrafo.debugHasOverflowShader, isFalse, reason: '«$motivo» se corta');
      }
    });

    testWidgets('a texto 2x cumple los tamaños de toque y las etiquetas', (tester) async {
      final handle = tester.ensureSemantics();
      await hastaJustificacion(tester, escala: 2, tamano: const Size(360, 640));

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}
