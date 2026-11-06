// QA de HU-UBI-003 (#511), pestaña «Mapa» con zonas: accesibilidad y tamaños (360×640 y 412×915,
// texto 1,0 y 2,0) con la zona propia, las demás y casas agrupadas; el nodo del lector con nombres
// raros. La vista nativa es la falsa del arnés.
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/zonas_del_mapa_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

List<UbicacionConResumen> _casas() => [
  filaLista('par-1', numero: '1', metrosAlNorte: 80),
  filaLista('par-2', numero: '2', metrosAlNorte: 80),
];

void main() {
  group('QA #511: accesibilidad con zonas, 360×640 y 412×915, texto 1,0 y 2,0', () {
    for (final (tamano, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 1.0),
      (const Size(412, 915), 2.0),
    ]) {
      testWidgets('dada la zona propia, ajenas y casas agrupadas a ${tamano.width.toInt()}×'
          '${tamano.height.toInt()} texto $escala, entonces no desborda, los botones tienen 48/44 dp, '
          'etiqueta y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        final zonas = ZonasDelMapaFalsas([
          zonaCuadrada('a', nombre: 'Cerro Norte', propia: true),
          zonaCuadrada('b', nombre: 'La Teja', lon: -56.1),
          zonaCuadrada('c', nombre: 'Barrio ${'muy ' * 40}largo', lon: -56.0),
        ]);
        await montarMapaUbicaciones(
          tester,
          repo: RepoListaFalso(_casas()),
          otrosOverrides: [zonas.sobrescribe],
          tamano: tamano,
          escala: escala,
        );

        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Mapa de ubicaciones. Tu zona: Cerro Norte.'), findsOneWidget);
        expect(find.textContaining('La Teja', findRichText: true), findsNothing);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }

    testWidgets(
      'dados nombres con emoji y caracteres especiales, entonces llegan enteros al mapa y al '
      'lector sin romper nada',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final zonas = ZonasDelMapaFalsas([
          zonaCuadrada('a', nombre: 'Ñandú 🌳 <b>&"\'', propia: true),
          zonaCuadrada('b', nombre: 'Otra', lon: -56.1),
        ]);
        final m = await montarMapaUbicaciones(
          tester,
          otrosOverrides: [zonas.sobrescribe],
          tamano: const Size(360, 640),
          escala: 2,
        );

        expect(m.mapa.config!.zonas, hasLength(1));
        expect(
          find.bySemanticsLabel('Mapa de ubicaciones. Tu zona: Ñandú 🌳 <b>&"\'.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        semantica.dispose();
      },
    );
  });
}
