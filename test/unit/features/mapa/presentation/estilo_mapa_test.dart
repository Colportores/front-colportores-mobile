// El estilo MapLibre que se arma a partir del de backend (#286): es JSON puro, se prueba sin la
// vista nativa.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:flutter_test/flutter_test.dart';

const _montevideo = Coordenadas(lat: -34.88761, lon: -56.13024);
const _recursos = '/data/user/0/uy.colportores/files/mapa/basemaps-5.7.2-1';

ConfigVistaMapa _config({
  FuenteMapa fuente = const FuenteMapa.sinTiles(),
  List<PuntoMapa> puntos = const [],
  bool agrupar = false,
  CirculoPrecision? precision,
  Color fondo = ColoresMapa.fondo,
  Color colorNuevo = const Color(0xFF0B6E4F),
}) => ConfigVistaMapa(
  fuente: fuente,
  camaraInicial: const CamaraMapa(centro: _montevideo, zoom: 16),
  zoomMinimo: 3,
  zoomMaximo: 19,
  interaccion: const InteraccionMapa(),
  dobleToqueZoom: true,
  fondo: fondo,
  colorNuevo: colorNuevo,
  puntos: puntos,
  agruparPuntos: agrupar,
  precision: precision,
  puntosTocables: false,
);

void main() {
  late String estiloBase;
  late Map<String, dynamic> base;

  setUpAll(() {
    estiloBase = File('assets/mapa/estilo/colportores.json').readAsStringSync();
    base = jsonDecode(estiloBase) as Map<String, dynamic>;
  });

  Map<String, dynamic> construir(ConfigVistaMapa config) =>
      jsonDecode(
            ConstructorEstiloMapa.construir(
              estiloBase: estiloBase,
              directorioRecursos: _recursos,
              config: config,
            ),
          )
          as Map<String, dynamic>;

  List<Map<String, dynamic>> capas(Map<String, dynamic> estilo) => [
    for (final capa in estilo['layers'] as List<dynamic>) capa as Map<String, dynamic>,
  ];

  Map<String, dynamic> capa(Map<String, dynamic> estilo, String id) =>
      capas(estilo).singleWhere((c) => c['id'] == id);

  group('el estilo de backend que viaja en la app', () {
    test('trae la fuente de tiles a reemplazar y la atribución de OpenStreetMap', () {
      final fuentes = base['sources'] as Map<String, dynamic>;
      final tiles = fuentes[ConstructorEstiloMapa.fuenteTiles] as Map<String, dynamic>;

      expect(tiles['url'], 'pmtiles://REEMPLAZAR');
      expect(tiles['attribution'], contains('OpenStreetMap'));
    });

    test('todas sus tipografías y sus sprites están en los assets de la app', () {
      final fuentes = <String>{};
      void juntar(Object? valor) {
        if (valor is String && valor.startsWith('NotoSans-')) fuentes.add(valor);
        if (valor is List) valor.forEach(juntar);
      }

      for (final capa in capas(base)) {
        juntar((capa['layout'] as Map<String, dynamic>?)?['text-font']);
      }

      expect(fuentes, isNotEmpty);
      for (final fuente in fuentes) {
        for (final rango in ['0-255', '256-511', '8192-8447']) {
          expect(
            File('assets/mapa/glyphs/$fuente/$rango.pbf').existsSync(),
            isTrue,
            reason: '$fuente/$rango.pbf',
          );
        }
      }
      for (final archivo in ['grayscale.json', 'grayscale.png', 'grayscale@2x.json']) {
        expect(File('assets/mapa/sprites/$archivo').existsSync(), isTrue, reason: archivo);
      }
    });
  });

  group('ConstructorEstiloMapa.construir', () {
    test('con el paquete descargado apunta al archivo local', () {
      final estilo = construir(_config(fuente: const FuenteMapa.offline('/data/uy.pmtiles')));

      final tiles =
          (estilo['sources'] as Map<String, dynamic>)[ConstructorEstiloMapa.fuenteTiles]
              as Map<String, dynamic>;
      expect(tiles['url'], 'pmtiles://file:///data/uy.pmtiles');
      // El resto de la fuente (atribución, tipo) queda como lo publicó backend.
      expect(tiles['type'], 'vector');
      expect(tiles['attribution'], contains('OpenStreetMap'));
      expect(
        capas(estilo).where((c) => c['source'] == ConstructorEstiloMapa.fuenteTiles),
        isNotEmpty,
      );
    });

    test('online apunta al archivo del bucket', () {
      final estilo = construir(_config(fuente: const FuenteMapa.online('https://s/uy.pmtiles')));

      final tiles =
          (estilo['sources'] as Map<String, dynamic>)[ConstructorEstiloMapa.fuenteTiles]
              as Map<String, dynamic>;
      expect(tiles['url'], 'pmtiles://https://s/uy.pmtiles');
    });

    test('los glyphs y los sprites salen del almacenamiento interno, no de la red', () {
      final estilo = construir(_config());

      expect(estilo['glyphs'], 'file://$_recursos/glyphs/{fontstack}/{range}.pbf');
      expect(estilo['sprite'], 'file://$_recursos/sprites/grayscale');
      expect(jsonEncode(estilo), isNot(contains('ejemplo.invalid')));
      expect(jsonEncode(estilo), isNot(contains('REEMPLAZAR')));
    });

    test('sin tiles quita la fuente y todas las capas que leen de ella', () {
      final estilo = construir(_config());

      expect(
        (estilo['sources'] as Map<String, dynamic>).containsKey(ConstructorEstiloMapa.fuenteTiles),
        isFalse,
      );
      expect(capas(estilo).where((c) => c['source'] == ConstructorEstiloMapa.fuenteTiles), isEmpty);
      // Queda el fondo: es todo lo que se ve.
      expect(capas(estilo).first['type'], 'background');
    });

    test('el fondo toma el color pedido', () {
      final estilo = construir(_config(fondo: const Color(0xFFE8F0EC)));

      expect(capas(estilo).first['paint'], {'background-color': '#E8F0EC'});
    });

    test('las capas propias van arriba de las del mapa', () {
      final estilo = construir(_config(fuente: const FuenteMapa.online('https://s/uy.pmtiles')));
      final ids = [for (final c in capas(estilo)) c['id'] as String];
      final primeraPropia = ids.indexWhere((id) => id.startsWith('colportores:'));

      expect(primeraPropia, (base['layers'] as List<dynamic>).length);
      expect(ids.skip(primeraPropia).every((id) => id.startsWith('colportores:')), isTrue);
    });

    test('es consistente: ids únicos y cada capa lee de una fuente que existe', () {
      for (final fuente in const [
        FuenteMapa.sinTiles(),
        FuenteMapa.offline('/x.pmtiles'),
        FuenteMapa.online('https://s/x.pmtiles'),
      ]) {
        final estilo = construir(_config(fuente: fuente, agrupar: true));
        final fuentes = (estilo['sources'] as Map<String, dynamic>).keys.toSet();
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        expect(ids.toSet(), hasLength(ids.length));
        for (final c in capas(estilo)) {
          if (c['type'] == 'background') continue;
          expect(fuentes, contains(c['source']), reason: c['id'] as String);
        }
      }
    });

    test('las capas que responden al toque existen', () {
      final ids = [for (final c in capas(construir(_config()))) c['id'] as String];

      for (final tocable in ConstructorEstiloMapa.capasTocables) {
        expect(ids, contains(tocable));
      }
    });

    test('los textos de las capas propias usan una tipografía que está en la app', () {
      for (final c in capas(construir(_config()))) {
        if (!(c['id'] as String).startsWith('colportores:')) continue;
        final fuentes = (c['layout'] as Map<String, dynamic>?)?['text-font'] as List<dynamic>?;
        if (fuentes == null) continue;
        for (final fuente in fuentes) {
          expect(Directory('assets/mapa/glyphs/$fuente').existsSync(), isTrue);
        }
      }
    });

    group('puntos', () {
      test('sin agrupar la fuente es un GeoJSON común', () {
        final fuentes = construir(_config())['sources'] as Map<String, dynamic>;
        final puntos = fuentes[ConstructorEstiloMapa.fuentePuntos] as Map<String, dynamic>;

        expect(puntos['type'], 'geojson');
        expect(puntos.containsKey('cluster'), isFalse);
      });

      test('agrupados la fuente hace cluster, con su radio y su zoom máximo', () {
        final fuentes = construir(_config(agrupar: true))['sources'] as Map<String, dynamic>;
        final puntos = fuentes[ConstructorEstiloMapa.fuentePuntos] as Map<String, dynamic>;

        expect(puntos['cluster'], isTrue);
        expect(puntos['clusterRadius'], 44);
        expect(puntos['clusterMaxZoom'], 17);
      });

      test('cada punto es un Feature con [lon, lat] y sus propiedades', () {
        final geojson = ConstructorEstiloMapa.coleccionPuntos(const [
          PuntoMapa(id: 'm1', coordenadas: _montevideo),
          PuntoMapa(
            id: 'c1',
            coordenadas: Coordenadas(lat: -34.9, lon: -56.2),
            estilo: EstiloPunto.candidata,
            letra: 'A',
          ),
        ]);

        final features = geojson['features'] as List<dynamic>;
        expect(geojson['type'], 'FeatureCollection');
        expect(features, hasLength(2));
        final primero = features[0] as Map<String, dynamic>;
        expect((primero['geometry'] as Map<String, dynamic>)['coordinates'], [
          -56.13024,
          -34.88761,
        ]);
        expect(primero['properties'], {'id': 'm1', 'estilo': 'contexto'});
        final segundo = features[1] as Map<String, dynamic>;
        expect(segundo['properties'], {'id': 'c1', 'estilo': 'candidata', 'letra': 'A'});
      });

      test('sin puntos la colección está vacía', () {
        expect(ConstructorEstiloMapa.coleccionPuntos(const [])['features'], isEmpty);
      });

      test('la fuente lleva los puntos que se le dieron', () {
        final fuentes =
            construir(
                  _config(
                    puntos: const [PuntoMapa(id: 'a', coordenadas: _montevideo)],
                  ),
                )['sources']
                as Map<String, dynamic>;
        final puntos = fuentes[ConstructorEstiloMapa.fuentePuntos] as Map<String, dynamic>;

        expect(
          ((puntos['data'] as Map<String, dynamic>)['features'] as List<dynamic>),
          hasLength(1),
        );
      });

      test('cada estilo tiene su capa, filtrada por estilo y sin tocar a los grupos', () {
        final estilo = construir(_config(agrupar: true));

        for (final (id, nombre) in [
          (ConstructorEstiloMapa.capaContexto, 'contexto'),
          (ConstructorEstiloMapa.capaCandidata, 'candidata'),
          (ConstructorEstiloMapa.capaNuevo, 'nuevo'),
          (ConstructorEstiloMapa.capaGps, 'gps'),
        ]) {
          final filtro = capa(estilo, id)['filter'];
          expect(filtro, [
            'all',
            [
              '!',
              ['has', 'point_count'],
            ],
            [
              '==',
              ['get', 'estilo'],
              nombre,
            ],
          ], reason: id);
        }
      });

      test('los grupos se dibujan con su cantidad', () {
        final estilo = construir(_config(agrupar: true));

        expect(capa(estilo, ConstructorEstiloMapa.capaGrupos)['filter'], ['has', 'point_count']);
        final cuenta = capa(estilo, 'colportores:grupos-cuenta');
        expect((cuenta['layout'] as Map<String, dynamic>)['text-field'], [
          'get',
          'point_count_abbreviated',
        ]);
      });

      test('la letra de la candidata solo se dibuja si la tiene', () {
        final letra = capa(construir(_config()), 'colportores:candidata-letra');

        expect(letra['filter'], contains(equals(['has', 'letra'])));
        expect((letra['layout'] as Map<String, dynamic>)['text-field'], ['get', 'letra']);
      });

      test('el punto nuevo toma el color primario del tema', () {
        final estilo = construir(_config(colorNuevo: const Color(0xFF123456)));

        final paint =
            capa(estilo, ConstructorEstiloMapa.capaNuevo)['paint'] as Map<String, dynamic>;
        expect(paint['circle-color'], '#123456');
      });
    });

    group('radio de precisión', () {
      test('sin círculo la fuente no tiene geometrías', () {
        final poligono = ConstructorEstiloMapa.poligonoPrecision(null);

        expect(poligono['type'], 'FeatureCollection');
        expect(poligono['features'], isEmpty);
      });

      test('un radio que no se puede dibujar tampoco', () {
        for (final radio in [0.0, -3.0, double.nan, double.infinity]) {
          final poligono = ConstructorEstiloMapa.poligonoPrecision(
            CirculoPrecision(centro: _montevideo, radioMetros: radio),
          );
          expect(poligono['features'], isEmpty, reason: '$radio');
        }
      });

      test('un círculo válido es un polígono cerrado en [lon, lat]', () {
        final poligono = ConstructorEstiloMapa.poligonoPrecision(
          const CirculoPrecision(centro: _montevideo, radioMetros: 12),
        );

        final features = poligono['features'] as List<dynamic>;
        expect(features, hasLength(1));
        final geometria =
            (features.single as Map<String, dynamic>)['geometry'] as Map<String, dynamic>;
        expect(geometria['type'], 'Polygon');
        final anillo = ((geometria['coordinates'] as List<dynamic>).single as List<dynamic>)
            .cast<List<dynamic>>();
        expect(anillo.first, anillo.last);
        for (final v in anillo) {
          final punto = Coordenadas(lat: v[1] as double, lon: v[0] as double);
          expect(_montevideo.distanciaMetrosA(punto), closeTo(12, 0.05));
        }
      });

      test('la fuente de precisión sale en el estilo', () {
        final estilo = construir(
          _config(precision: const CirculoPrecision(centro: _montevideo, radioMetros: 12)),
        );

        final fuentes = estilo['sources'] as Map<String, dynamic>;
        final precision = fuentes[ConstructorEstiloMapa.fuentePrecision] as Map<String, dynamic>;
        expect(
          ((precision['data'] as Map<String, dynamic>)['features'] as List<dynamic>),
          hasLength(1),
        );
        expect(capa(estilo, 'colportores:precision-relleno')['type'], 'fill');
        expect(capa(estilo, 'colportores:precision-borde')['type'], 'line');
      });
    });
  });
}
