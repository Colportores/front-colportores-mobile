// QA de las vistas 03 y 04 (#193): medidas de texto y de solapes con las fuentes reales del proyecto.
//
// Con la fuente de prueba de `flutter_test` (Ahem) cada letra mide un cuadrado y los avisos que
// flotan sobre el mapa parecen más grandes de lo que son, así que acá se cargan Inter, Source Serif 4
// y JetBrains Mono. El contraste (`textContrastGuideline`) no se prueba acá: con texto antialiasado
// da falsos negativos en letra chica; está en `alta_ubicacion_qa_test.dart`.
//
// Los hallazgos de QA ya arreglados quedan como tests normales (el implementador les sacó el `skip`).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/campos_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_duplicado_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart';

/// La tarjeta roja de «Sin conexión a internet» (06C·05), arriba de la hoja de abajo (no sobre el
/// mapa): antes era un recuadro de «Sin tiles para esta zona…», reemplazado por #190.
Finder get _avisoSinTiles => find.byType(AvisoMapaConectado);

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
    // El aviso del mapa («Sin conexión a internet», 06C·05) va en la hoja de abajo, no flotando sobre
    // el mapa: antes tapaba el botón «Activar GPS» del aviso de sin GPS.
    testWidgets('sin GPS, el aviso «Sin conexión…» no tapa el botón «Activar GPS»', (tester) async {
      await montarAlta(
        tester,
        gps: gpsSinPermiso,
        tamano: const Size(360, 640),
        situacion: situacionSinConexion,
      );

      _sinSolape(tester, _avisoSinTiles, _botonActivarGps, 'sin tiles vs «Activar GPS»');
      _sinSolape(tester, _avisoSinTiles, find.text(TextosAlta.tocar), 'sin tiles vs pista');
    });

    // A texto 2x el aviso «Sin conexión…» (4 renglones) tampoco se monta sobre la pista del pin, el pin
    // ni «Volver a mi ubicación».
    testWidgets(
      'con GPS y texto 2x, el aviso «Sin conexión…» no tapa el pin, la pista ni «Volver a mi ubicación»',
      (tester) async {
        await montarAlta(
          tester,
          tamano: const Size(360, 640),
          escala: 2,
          situacion: situacionSinConexion,
        );

        _sinSolape(tester, _avisoSinTiles, find.byType(PinAlta), 'sin tiles vs pin');
        _sinSolape(tester, _avisoSinTiles, find.text(TextosAlta.mover), 'sin tiles vs pista');
        _sinSolape(
          tester,
          _avisoSinTiles,
          find.byTooltip('Volver a mi ubicación'),
          'sin tiles vs «Volver a mi ubicación»',
        );
      },
    );

    testWidgets('a 412×915 el aviso «Sin conexión…» no se pisa con nada', (tester) async {
      await montarAlta(
        tester,
        gps: gpsSinPermiso,
        tamano: const Size(412, 915),
        situacion: situacionSinConexion,
      );

      _sinSolape(tester, _avisoSinTiles, _botonActivarGps, 'sin tiles vs «Activar GPS»');
      _sinSolape(tester, _avisoSinTiles, find.text(TextosAlta.tocar), 'sin tiles vs pista');
    });

    // El selector de tipo y el campo de ciudad no parten una palabra a mitad («Negoc/io»,
    // «Edifici/o», «Montevide/o»): si no entran en la fila, el selector pasa a un botón por renglón y
    // el origen de la ciudad baja al renglón de abajo.
    for (final (tamano, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 2.0),
    ]) {
      testWidgets(
        'a ${tamano.width.toInt()}×${tamano.height.toInt()} y texto $escala ningún tipo ni la '
        'ciudad se parten a mitad de palabra',
        (tester) async {
          await montarAlta(tester, tamano: tamano, escala: escala);

          expect(tester.takeException(), isNull);
          for (final palabra in ['Casa', 'Negocio', 'Edificio', 'Montevideo']) {
            final parrafo = tester.renderObject<RenderParagraph>(find.text(palabra));
            // Una palabra partida en dos renglones da dos cajas de selección.
            final cajas = parrafo.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: palabra.length),
            );
            expect(cajas, hasLength(1), reason: '«$palabra» se parte');
          }
        },
      );
    }

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

  group('QA #193 (ronda 2) · vista 03 A·02 «Sin GPS» · el aviso de sin GPS en el mapa chico', () {
    final avisoSinGps = find.ancestor(
      of: find.text('Activar GPS'),
      matching: find.byType(AvisoAlta),
    );

    // El mapa de un teléfono es más chico que el del canvas (la hoja ocupa hasta el 62 % del alto):
    // a 360×640 mide ~243 px y a texto 2x el aviso solo mide ~250. Por eso el aviso va arriba de la hoja
    // de abajo, que se desplaza, y no flotando sobre el mapa: «Activar GPS» siempre se ve y se toca, y
    // el pin, el chip del GPS y la pista quedan libres.
    testWidgets('a texto 1x la pista del pin no se pisa con el aviso de sin GPS', (tester) async {
      await montarAlta(
        tester,
        gps: gpsSinPermiso,
        tamano: const Size(360, 640),
        situacion: situacionSinConexion,
      );

      _sinSolape(tester, avisoSinGps, find.text(TextosAlta.tocar), 'aviso sin GPS vs pista');
    });

    testWidgets('a texto 2x «Activar GPS» se ve y se puede tocar, y la pista no pisa el aviso', (
      tester,
    ) async {
      await montarAlta(tester, gps: gpsSinPermiso, tamano: const Size(360, 640), escala: 2);

      expect(find.text('Activar GPS').hitTestable(), findsOneWidget);
      _sinSolape(tester, avisoSinGps, find.text(TextosAlta.tocar), 'aviso sin GPS vs pista');
    });

    testWidgets('a 412×915 y texto 1x el aviso de sin GPS no se pisa con la pista', (tester) async {
      await montarAlta(
        tester,
        gps: gpsSinPermiso,
        tamano: const Size(412, 915),
        situacion: situacionSinConexion,
      );

      expect(find.text('Activar GPS').hitTestable(), findsOneWidget);
      _sinSolape(tester, avisoSinGps, find.text(TextosAlta.tocar), 'aviso sin GPS vs pista');
    });

    // El aviso entero está dentro de la pantalla, no cortado, y no tapa nada de lo que hay sobre el
    // mapa: el pin (sin punto todavía, punteado), el chip «Sin GPS» y el botón de cerrar.
    for (final (tamano, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 1.0),
    ]) {
      testWidgets(
        'a ${tamano.width.toInt()}×${tamano.height.toInt()} y texto $escala el aviso de sin GPS se '
        'lee completo y no tapa el pin, el chip ni «Cerrar»',
        (tester) async {
          await montarAlta(tester, gps: gpsSinPermiso, tamano: tamano, escala: escala);

          expect(tester.takeException(), isNull);
          final aviso = tester.getRect(avisoSinGps);
          expect(aviso.left, greaterThanOrEqualTo(0), reason: 'el aviso se sale de la pantalla');
          expect(aviso.top, greaterThanOrEqualTo(0), reason: 'el aviso se sale de la pantalla');
          expect(aviso.right, lessThanOrEqualTo(tamano.width), reason: 'se sale de la pantalla');
          expect(aviso.bottom, lessThanOrEqualTo(tamano.height), reason: 'se sale de la pantalla');
          final texto = tester.renderObject<RenderParagraph>(find.text(TextosAlta.sinGpsAviso));
          expect(texto.didExceedMaxLines, isFalse, reason: 'el texto del aviso se corta');
          _sinSolape(tester, avisoSinGps, find.byType(PinAlta), 'aviso sin GPS vs pin');
          _sinSolape(tester, avisoSinGps, find.text('Sin GPS'), 'aviso sin GPS vs chip del GPS');
          _sinSolape(tester, avisoSinGps, find.byTooltip(TextosAlta.cerrar), 'aviso vs «Cerrar»');
        },
      );
    }

    testWidgets('a 360×640 y texto 2x tocar «Activar GPS» pide lo que corresponde', (tester) async {
      final gps = gpsSinPermiso;
      await montarAlta(tester, gps: gps, tamano: const Size(360, 640), escala: 2);

      await tester.tap(find.text('Activar GPS'));
      await asentar(tester);

      expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
    });
  });

  group('QA #193 · vista 04 · paso de justificación (B·03) con las fuentes reales', () {
    // A texto 2x los motivos sugeridos parten en renglones en vez de cortarse («Otra puerta en el
    // mism…»): ya no son `ActionChip` (una sola línea) sino botones que crecen con el texto.
    testWidgets('a texto 2x cada motivo sugerido se lee completo, sin cortarse', (tester) async {
      await hastaJustificacion(tester, escala: 2, tamano: const Size(360, 640));

      for (final motivo in TextosDuplicado.motivos) {
        final parrafo = tester.renderObject<RenderParagraph>(find.text(motivo));
        expect(parrafo.debugHasOverflowShader, isFalse, reason: '«$motivo» se corta');
        expect(parrafo.didExceedMaxLines, isFalse, reason: '«$motivo» se corta');
      }
    });

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

  // Lo mismo que se probó en la vista 07 (#202, tanda 34): las insignias de los campos son compartidas
  // y el alta usa el mismo esqueleto de hoja.
  group('vistas 03 y 07 · campos compartidos en 360×640', () {
    testWidgets('a texto 2x las insignias «Del mapa» no se parten ni se salen de su columna', (
      tester,
    ) async {
      await montarAlta(tester, tamano: const Size(360, 640), escala: 2);
      await asentar(tester);

      final insignias = find.byType(InsigniaCampo);
      expect(insignias, findsWidgets);
      for (var i = 0; i < insignias.evaluate().length; i++) {
        final insignia = tester.getRect(insignias.at(i));
        expect(insignia.left, greaterThanOrEqualTo(0));
        expect(insignia.right, lessThanOrEqualTo(360), reason: 'la insignia no se sale de la hoja');
      }
      final textos = find.text('Del mapa');
      for (var i = 0; i < textos.evaluate().length; i++) {
        final parrafo = tester.renderObject<RenderParagraph>(textos.at(i));
        final cajas = parrafo.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 'Del mapa'.length),
        );
        expect(cajas, hasLength(1), reason: '«Del mapa» no se parte en dos renglones');
      }
    });

    // skip: #305 — en 360×640 con un campo editado «Registrar» queda cortado al pie (termina en 712 dp):
    // la hoja del alta es un solo scroll con el botón adentro. Se arregla como la 07 (botón fijo al
    // pie, ver #202) y entonces se le saca el `skip`.
    testWidgets('con un campo editado, «Registrar» queda entero a la vista', (tester) async {
      await montarAlta(tester, tamano: const Size(360, 640));
      await tester.enterText(find.byType(TextField).at(1), '1238');
      await asentar(tester);

      final r = tester.getRect(find.widgetWithText(FilledButton, TextosAlta.registrar));
      expect(r.bottom, lessThanOrEqualTo(640), reason: '«Registrar» queda cortado al pie');
      expect(r.top, greaterThanOrEqualTo(0));
    }, skip: true);
  });
}
