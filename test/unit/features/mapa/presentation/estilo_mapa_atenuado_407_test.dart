// El mapa atenúa lo que no está agendado (vista 06, 06C·03, #407): un punto atenuado lleva la
// propiedad `atenuado` y cada capa de puntos multiplica su opacidad por .3; un grupo se atenúa si
// ninguna de sus casas está viva.
import 'dart:convert';

import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/assets_de_lib_mapa.dart';

const _montevideo = Coordenadas(lat: -34.88761, lon: -56.13024);

ConfigVistaMapa _config(List<PuntoMapa> puntos, {bool agrupar = true}) => ConfigVistaMapa(
  fuente: const FuenteMapa.sinTiles(),
  camaraInicial: const CamaraMapa(centro: _montevideo, zoom: 16),
  zoomMinimo: 3,
  zoomMaximo: 19,
  interaccion: const InteraccionMapa(),
  dobleToqueZoom: true,
  fondo: ColoresMapa.fondo,
  colorNuevo: const Color(0xFF0B6E4F),
  puntos: puntos,
  agruparPuntos: agrupar,
  precision: null,
  cercania: null,
  puntosTocables: true,
);

void main() {
  late String estiloBase;

  setUpAll(() => estiloBase = estiloDeLibMapa());

  Map<String, dynamic> construir(ConfigVistaMapa config) =>
      jsonDecode(ConstructorEstiloMapa.construirSinRecursos(estiloBase: estiloBase, config: config))
          as Map<String, dynamic>;

  List<Map<String, dynamic>> capasDe(Map<String, dynamic> estilo, String fuente) => [
    for (final capa in estilo['layers'] as List<dynamic>)
      if ((capa as Map<String, dynamic>)['source'] == fuente) capa,
  ];

  const factorPunto = [
    'case',
    [
      '==',
      ['get', 'atenuado'],
      true,
    ],
    .3,
    1,
  ];
  const factorGrupo = [
    'case',
    [
      '==',
      ['get', 'vivos'],
      0,
    ],
    .3,
    1,
  ];

  group('PuntoMapa.atenuado en los datos', () {
    test('el atenuado lleva `atenuado: true`; el otro no lleva la propiedad', () {
      const puntos = [
        PuntoMapa(id: 'a', coordenadas: _montevideo, atenuado: true),
        PuntoMapa(id: 'b', coordenadas: _montevideo),
        PuntoMapa(
          id: 'c',
          coordenadas: _montevideo,
          estilo: EstiloPunto.cercano,
          etiqueta: '12',
          atenuado: true,
        ),
      ];
      final agrupables = ConstructorEstiloMapa.coleccionPuntos(puntos);
      final libres = ConstructorEstiloMapa.coleccionPuntosLibres(puntos);
      Map<String, dynamic> props(Map<String, dynamic> coleccion, String id) =>
          (coleccion['features'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((f) => f['properties'] as Map<String, dynamic>)
              .firstWhere((p) => p['id'] == id);

      expect(props(agrupables, 'a')['atenuado'], isTrue);
      expect(props(agrupables, 'b').containsKey('atenuado'), isFalse);
      expect(props(libres, 'c')['atenuado'], isTrue);
    });

    test('atenuado cuenta para la igualdad (un cambio vuelve a mandar los puntos)', () {
      expect(
        const PuntoMapa(id: 'a', coordenadas: _montevideo),
        isNot(const PuntoMapa(id: 'a', coordenadas: _montevideo, atenuado: true)),
      );
    });
  });

  group('las capas', () {
    test(
      'cada capa de puntos (no de grupos) multiplica su opacidad por el factor del atenuado',
      () {
        final estilo = construir(_config(const []));
        final capas = [
          ...capasDe(estilo, ConstructorEstiloMapa.fuentePuntos),
          ...capasDe(estilo, ConstructorEstiloMapa.fuentePuntosLibres),
        ];
        expect(capas, isNotEmpty);
        for (final capa in capas) {
          final paint = capa['paint'] as Map<String, dynamic>;
          final esGrupo = capa['filter'].toString() == ['has', 'point_count'].toString();
          final factor = esGrupo ? factorGrupo : factorPunto;
          final propiedades = capa['type'] == 'circle'
              ? ['circle-opacity', 'circle-stroke-opacity']
              : ['icon-opacity', 'text-opacity'];
          for (final propiedad in propiedades) {
            final valor = paint[propiedad];
            final texto = factor.toString();
            expect(
              valor.toString() == texto ||
                  (valor is List && valor.first == '*' && valor.last.toString() == texto),
              isTrue,
              reason: '${capa['id']}.$propiedad = $valor',
            );
          }
        }
      },
    );

    test('la sombra del punto de contexto conserva su .4 y lo multiplica', () {
      final estilo = construir(_config(const []));
      final sombra = capasDe(
        estilo,
        ConstructorEstiloMapa.fuentePuntos,
      ).firstWhere((c) => c['id'] == 'colportores:contexto-sombra');

      expect((sombra['paint'] as Map)['circle-opacity'], ['*', .4, factorPunto]);
    });

    test('los grupos suman sus casas vivas (`vivos`) para saber si atenuarse', () {
      final estilo = construir(_config(const []));
      final fuente =
          (estilo['sources'] as Map)[ConstructorEstiloMapa.fuentePuntos] as Map<String, dynamic>;

      expect(fuente['clusterProperties'], {
        'vivos': [
          '+',
          ['case', factorPunto[1], 0, 1],
        ],
      });
    });

    test('sin agrupar no hay `clusterProperties`', () {
      final estilo = construir(_config(const [], agrupar: false));
      final fuente =
          (estilo['sources'] as Map)[ConstructorEstiloMapa.fuentePuntos] as Map<String, dynamic>;

      expect(fuente.containsKey('clusterProperties'), isFalse);
    });

    test('las zonas, la precisión y la cercanía no se atenúan', () {
      final estilo = construir(_config(const []));
      for (final capa in estilo['layers'] as List<dynamic>) {
        final c = capa as Map<String, dynamic>;
        final fuente = c['source'];
        if (fuente == ConstructorEstiloMapa.fuentePuntos ||
            fuente == ConstructorEstiloMapa.fuentePuntosLibres) {
          continue;
        }
        expect(c['paint'].toString(), isNot(contains('atenuado')), reason: '${c['id']}');
      }
    });
  });
}
