// QA de HU-UBI-003 (#654, PR #664): el mapa del colportor dibuja y nombra solo sus zonas. No hay canvas
// del teléfono para las zonas (decisión de Cristian, 27/10): la cobertura son los criterios del issue
// y los casos límite. La vista nativa es la falsa del arnés (`config.zonas`) y el estilo se construye
// con el constructor real, así que lo que se mira es lo que el mapa recibe y lo que oye el lector.
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/zonas_del_mapa_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';

const _mapa = 'Mapa de ubicaciones';

List<UbicacionConResumen> _casas() => [
  filaLista('par-1', numero: '1', metrosAlNorte: 80),
  filaLista('par-2', numero: '2', metrosAlNorte: 80),
];

Future<MontajeMapaUbicaciones> _montar(
  WidgetTester tester,
  ZonasDelMapaFalsas zonas, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) => montarMapaUbicaciones(
  tester,
  repo: RepoListaFalso(_casas()),
  otrosOverrides: [zonas.sobrescribe],
  tamano: tamano,
  escala: escala,
);

List<String> _dibujadas(MontajeMapaUbicaciones m) => [for (final z in m.mapa.config!.zonas) z.id];

void main() {
  group('QA #654 · criterio «solo se dibuja (y se rotula) la zona del colportor»', () {
    testWidgets(
      'dado un pull que trae una zona ajena después de la propia, cuando llega, entonces no se '
      'dibuja ni se nombra',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final zonas = ZonasDelMapaFalsas([zonaCuadrada('a', nombre: 'Cerro', propia: true)]);
        final m = await _montar(tester, zonas);
        expect(_dibujadas(m), ['a']);

        zonas.emitir([
          zonaCuadrada('a', nombre: 'Cerro', propia: true),
          zonaCuadrada('b', nombre: 'La Teja', lon: -56.1),
        ]);
        await asentarLista(tester);

        expect(_dibujadas(m), ['a']);
        expect(find.bySemanticsLabel('$_mapa. Tu zona: Cerro.'), findsOneWidget);
        expect(find.textContaining('Teja', findRichText: true), findsNothing);
        semantica.dispose();
      },
    );

    testWidgets(
      'dado un pull que le quita la zona propia y deja las ajenas, entonces el mapa queda sin zonas '
      'y el lector oye solo «Mapa de ubicaciones»',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final zonas = ZonasDelMapaFalsas([
          zonaCuadrada('a', nombre: 'Cerro', propia: true),
          zonaCuadrada('b', nombre: 'La Teja', lon: -56.1),
        ]);
        final m = await _montar(tester, zonas);
        expect(_dibujadas(m), ['a']);

        zonas.emitir([zonaCuadrada('b', nombre: 'La Teja', lon: -56.1)]);
        await asentarLista(tester);

        expect(_dibujadas(m), isEmpty);
        expect(find.bySemanticsLabel(_mapa), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantica.dispose();
      },
    );

    testWidgets(
      'dado un colportor con dos zonas propias (dos campañas) y una ajena, entonces dibuja las dos '
      'suyas y el lector las une',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final zonas = ZonasDelMapaFalsas([
          zonaCuadrada('a', nombre: 'Cerro', propia: true),
          zonaCuadrada('b', nombre: 'La Teja', lon: -56.1),
          zonaCuadrada('c', nombre: 'Belvedere', propia: true, lon: -56.0),
        ]);
        final m = await _montar(tester, zonas);

        expect(_dibujadas(m), ['a', 'c']);
        expect(find.bySemanticsLabel('$_mapa. Tu zona: Cerro y Belvedere.'), findsOneWidget);
        semantica.dispose();
      },
    );

    testWidgets(
      'dada una falla de lectura después de dibujar la propia, entonces el mapa conserva la propia '
      'y no cuela las ajenas al recuperarse',
      (tester) async {
        final zonas = ZonasDelMapaFalsas([
          zonaCuadrada('a', propia: true),
          zonaCuadrada('b', lon: -56.1),
        ]);
        final m = await _montar(tester, zonas);

        zonas.fallar();
        await asentarLista(tester);
        expect(_dibujadas(m), ['a']);
        expect(tester.takeException(), isNull);

        zonas.emitir([zonaCuadrada('a', propia: true), zonaCuadrada('b', lon: -56.1)]);
        await asentarLista(tester);
        expect(_dibujadas(m), ['a']);
      },
    );

    testWidgets(
      'dadas 300 zonas ajenas y una propia, entonces se dibuja una sola y el mapa no desborda',
      (tester) async {
        final zonas = ZonasDelMapaFalsas([
          for (var i = 0; i < 300; i++) zonaCuadrada('o$i', lon: -57 + i * .01, lado: .005),
          zonaCuadrada('mia', propia: true),
        ]);
        final m = await _montar(tester, zonas);

        expect(_dibujadas(m), ['mia']);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('QA #654 · colportor sin zona asignada: tamaños y accesibilidad', () {
    for (final (tamano, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 1.0),
      (const Size(412, 915), 2.0),
    ]) {
      testWidgets('dada una ciudad con zonas solo de otros a ${tamano.width.toInt()}×'
          '${tamano.height.toInt()} texto $escala, entonces no dibuja ninguna, no desborda y '
          'cumple las guías', (tester) async {
        final semantica = tester.ensureSemantics();
        final zonas = ZonasDelMapaFalsas([
          zonaCuadrada('b', nombre: 'La Teja', lon: -56.1),
          zonaCuadrada('c', nombre: 'Barrio ${'muy ' * 40}largo', lon: -56.0),
        ]);
        final m = await _montar(tester, zonas, tamano: tamano, escala: escala);

        expect(tester.takeException(), isNull);
        expect(_dibujadas(m), isEmpty);
        expect(find.bySemanticsLabel(_mapa), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  });

  group('QA #654 · estilo real con una ajena que llegara hasta el constructor', () {
    late String estiloBase;
    setUpAll(() => estiloBase = File('assets/mapa/estilo/colportores.json').readAsStringSync());

    ZonaMapa zona(String id, {required bool propia}) => zonaMapa(id, propia: propia);

    Map<String, dynamic> construir(List<ZonaMapa> zonas, {required bool conRecursos}) {
      final config = ConfigVistaMapa(
        fuente: const FuenteMapa.online('https://s/uy.pmtiles'),
        camaraInicial: CamaraMapa(centro: zonas.first.puntoRotulo!, zoom: 16),
        zoomMinimo: 3,
        zoomMaximo: 19,
        interaccion: const InteraccionMapa(),
        dobleToqueZoom: true,
        fondo: ColoresMapa.fondo,
        colorNuevo: const Color(0xFF0B6E4F),
        puntos: const [],
        agruparPuntos: true,
        precision: null,
        cercania: null,
        puntosTocables: true,
        zonas: zonas,
      );
      final json = conRecursos
          ? ConstructorEstiloMapa.construir(
              estiloBase: estiloBase,
              directorioRecursos: '/data/mapa/basemaps',
              config: config,
            )
          : ConstructorEstiloMapa.construirSinRecursos(estiloBase: estiloBase, config: config);
      return jsonDecode(json) as Map<String, dynamic>;
    }

    for (final conRecursos in [true, false]) {
      test('dado un estilo ${conRecursos ? 'con' : 'sin'} recursos, entonces ninguna capa de zonas '
          'deja pasar una zona con propia == false', () {
        final estilo = construir([
          zona('mia', propia: true),
          zona('ajena', propia: false),
        ], conRecursos: conRecursos);
        final capasZona = [
          for (final c in estilo['layers'] as List<dynamic>)
            if ((c as Map<String, dynamic>)['source'] == ConstructorEstiloMapa.fuenteZonas ||
                c['source'] == ConstructorEstiloMapa.fuenteZonasRotulos)
              c,
        ];

        expect(capasZona, isNotEmpty);
        for (final c in capasZona) {
          expect(
            c['filter'],
            equals([
              '==',
              ['get', 'propia'],
              true,
            ]),
            reason: 'la capa ${c['id']} tiene que filtrar por propia',
          );
          expect((c['id'] as String), isNot(contains('otras')));
        }
      });
    }
  });
}

/// Una [ZonaMapa] mínima con su punto de rótulo, para el constructor del estilo.
ZonaMapa zonaMapa(String id, {required bool propia}) =>
    ZonaMapa.desde(zonaCuadrada(id, propia: propia));
