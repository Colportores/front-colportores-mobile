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
  CirculoCercania? cercania,
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
  cercania: cercania,
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

  Map<String, dynamic> construirSinRecursos(ConfigVistaMapa config) =>
      jsonDecode(ConstructorEstiloMapa.construirSinRecursos(estiloBase: estiloBase, config: config))
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

    group('un paquete en partes (una ciudad en dos archivos)', () {
      const partes = FuenteMapa.offlineEnPartes(['/data/mvd-p1.pmtiles', '/data/mvd-p2.pmtiles']);

      Map<String, dynamic> fuenteDe(Map<String, dynamic> estilo, String nombre) =>
          (estilo['sources'] as Map<String, dynamic>)[nombre] as Map<String, dynamic>;

      test('arma una fuente por parte, con la misma atribución y el archivo de cada una', () {
        final estilo = construir(_config(fuente: partes));

        expect(fuenteDe(estilo, 'protomaps')['url'], 'pmtiles://file:///data/mvd-p1.pmtiles');
        expect(fuenteDe(estilo, 'protomaps-p2')['url'], 'pmtiles://file:///data/mvd-p2.pmtiles');
        expect(fuenteDe(estilo, 'protomaps-p2')['type'], 'vector');
        expect(fuenteDe(estilo, 'protomaps-p2')['attribution'], contains('OpenStreetMap'));
      });

      test('repite cada capa del mapa para la segunda parte, pegada a la de la primera, así el '
          'orden de apilado es el del estilo original', () {
        final original = capas(
          construir(_config(fuente: const FuenteMapa.offline('/data/a.pmtiles'))),
        );
        final estilo = construir(_config(fuente: partes));
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        final deTiles = original.where((c) => c['source'] == ConstructorEstiloMapa.fuenteTiles);
        expect(deTiles, isNotEmpty);
        for (final c in deTiles) {
          final i = ids.indexOf(c['id'] as String);
          expect(ids[i + 1], '${c['id']}-p2');
          final copia = capa(estilo, '${c['id']}-p2');
          expect(copia['source'], 'protomaps-p2');
          expect(
            {...copia}
              ..remove('id')
              ..remove('source'),
            {...c}
              ..remove('id')
              ..remove('source'),
          );
        }
        // Lo que no lee de los tiles (el fondo, las capas propias) no se repite.
        expect(capas(estilo).where((c) => c['type'] == 'background'), hasLength(1));
        expect(
          ids.where((id) => id.startsWith('colportores:')),
          isNot(anyElement(endsWith('-p2'))),
        );
      });

      test('es consistente: ids únicos y cada capa lee de una fuente que existe', () {
        final estilo = construir(_config(fuente: partes, agrupar: true));
        final fuentes = (estilo['sources'] as Map<String, dynamic>).keys.toSet();
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        expect(ids.toSet(), hasLength(ids.length));
        for (final c in capas(estilo)) {
          if (c['type'] == 'background') continue;
          expect(fuentes, contains(c['source']), reason: c['id'] as String);
        }
      });

      test('online y sin los recursos también se arma en partes', () {
        const online = FuenteMapa.onlineEnPartes(['https://s/a.pmtiles', 'https://s/b.pmtiles']);

        final estilo = construirSinRecursos(_config(fuente: online));

        expect(fuenteDe(estilo, 'protomaps-p2')['url'], 'pmtiles://https://s/b.pmtiles');
        final conTiles = capas(estilo).where((c) => c['source'] == 'protomaps-p2');
        expect(conTiles, isNotEmpty);
      });

      test('una sola parte arma el estilo de siempre, sin fuentes de más', () {
        final estilo = construir(
          _config(fuente: const FuenteMapa.offlineEnPartes(['/data/a.pmtiles'])),
        );

        expect((estilo['sources'] as Map<String, dynamic>).containsKey('protomaps-p2'), isFalse);
        expect(capas(estilo).where((c) => (c['id'] as String).endsWith('-p2')), isEmpty);
      });
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

    group('sin los glyphs y sprites (no se pudieron copiar)', () {
      const conTiles = FuenteMapa.online('https://s/uy.pmtiles');
      const puntos = [
        PuntoMapa(id: 'm1', coordenadas: _montevideo),
        PuntoMapa(id: 'gps', coordenadas: _montevideo, estilo: EstiloPunto.gps),
        PuntoMapa(id: 'c1', coordenadas: _montevideo, estilo: EstiloPunto.candidata, letra: 'A'),
      ];

      test('no apunta a glyphs ni a sprites', () {
        final estilo = construirSinRecursos(_config(fuente: conTiles));

        expect(estilo.containsKey('glyphs'), isFalse);
        expect(estilo.containsKey('sprite'), isFalse);
        expect(jsonEncode(estilo), isNot(contains('ejemplo.invalid')));
        expect(jsonEncode(estilo), isNot(contains('REEMPLAZAR')));
      });

      test('no queda ninguna capa que necesite tipografías o íconos', () {
        for (final fuente in const [FuenteMapa.sinTiles(), conTiles]) {
          final estilo = construirSinRecursos(_config(fuente: fuente, agrupar: true));

          for (final c in capas(estilo)) {
            expect(c['type'], isNot('symbol'), reason: c['id'] as String);
            final layout = (c['layout'] as Map<String, dynamic>?) ?? const {};
            expect(layout.containsKey('text-font'), isFalse, reason: c['id'] as String);
            expect(layout.containsKey('icon-image'), isFalse, reason: c['id'] as String);
            final paint = (c['paint'] as Map<String, dynamic>?) ?? const {};
            expect(paint.keys.where((k) => k.endsWith('-pattern')), isEmpty);
          }
        }
      });

      test('los tiles, los puntos y el radio del GPS se siguen viendo', () {
        final estilo = construirSinRecursos(
          _config(
            fuente: conTiles,
            puntos: puntos,
            precision: const CirculoPrecision(centro: _montevideo, radioMetros: 30),
          ),
        );
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        final tiles =
            (estilo['sources'] as Map<String, dynamic>)[ConstructorEstiloMapa.fuenteTiles]
                as Map<String, dynamic>;
        expect(tiles['url'], 'pmtiles://https://s/uy.pmtiles');
        expect(
          capas(estilo).where((c) => c['source'] == ConstructorEstiloMapa.fuenteTiles),
          isNotEmpty,
          reason: 'las calles (líneas y áreas) no necesitan recursos',
        );
        for (final tocable in ConstructorEstiloMapa.capasTocables) {
          expect(ids, contains(tocable));
        }
        expect(ids, contains('colportores:precision-relleno'));
        expect(ids, contains('colportores:gps-halo'));
        final fuentes = estilo['sources'] as Map<String, dynamic>;
        List<dynamic> features(String fuente) =>
            ((fuentes[fuente] as Map<String, dynamic>)['data'] as Map<String, dynamic>)['features']
                as List<dynamic>;
        expect(features(ConstructorEstiloMapa.fuentePuntos), hasLength(2));
        expect(features(ConstructorEstiloMapa.fuentePuntosLibres), hasLength(1));
      });

      test('es consistente: ids únicos y cada capa lee de una fuente que existe', () {
        for (final fuente in const [FuenteMapa.sinTiles(), conTiles]) {
          final estilo = construirSinRecursos(_config(fuente: fuente, agrupar: true));
          final fuentes = (estilo['sources'] as Map<String, dynamic>).keys.toSet();
          final ids = [for (final c in capas(estilo)) c['id'] as String];

          expect(ids.toSet(), hasLength(ids.length));
          for (final c in capas(estilo)) {
            if (c['type'] == 'background') continue;
            expect(fuentes, contains(c['source']), reason: c['id'] as String);
          }
        }
      });

      test('el fondo y el color de la ubicación nueva se aplican igual', () {
        final estilo = construirSinRecursos(
          _config(fondo: const Color(0xFFE8F0EC), colorNuevo: const Color(0xFF123456)),
        );

        expect(capas(estilo).first['paint'], {'background-color': '#E8F0EC'});
        final nuevo = capa(estilo, ConstructorEstiloMapa.capaNuevo);
        expect((nuevo['paint'] as Map<String, dynamic>)['circle-color'], '#123456');
      });

      test('con recursos sí están las capas de texto (el degradado es solo sin ellos)', () {
        final ids = [for (final c in capas(construir(_config()))) c['id'] as String];

        expect(ids, contains('colportores:grupos-cuenta'));
        expect(ids, contains('colportores:candidata-letra'));
        expect(capas(construir(_config())).where((c) => c['type'] == 'symbol'), isNotEmpty);
      });
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

      test('el GPS, el punto nuevo, el cercano y el seleccionado leen de la fuente que nunca se '
          'agrupa, filtrados por estilo', () {
        final estilo = construir(_config(agrupar: true));

        for (final (id, nombre) in [
          (ConstructorEstiloMapa.capaNuevo, 'nuevo'),
          (ConstructorEstiloMapa.capaGps, 'gps'),
          (ConstructorEstiloMapa.capaCercano, 'cercano'),
          (ConstructorEstiloMapa.capaSeleccionado, 'seleccionado'),
        ]) {
          final c = capa(estilo, id);
          expect(c['source'], ConstructorEstiloMapa.fuentePuntosLibres, reason: id);
          expect(c['filter'], [
            '==',
            ['get', 'estilo'],
            nombre,
          ], reason: id);
        }
        final libres =
            (estilo['sources'] as Map<String, dynamic>)[ConstructorEstiloMapa.fuentePuntosLibres]
                as Map<String, dynamic>;
        expect(libres.containsKey('cluster'), isFalse, reason: 'con agrupar: true también');
      });

      test('los puntos se reparten entre las dos fuentes según EstiloPunto.sinAgrupar', () {
        const puntos = [
          PuntoMapa(id: 'a', coordenadas: _montevideo),
          PuntoMapa(id: 'b', coordenadas: _montevideo, estilo: EstiloPunto.candidata, letra: 'A'),
          PuntoMapa(id: 'c', coordenadas: _montevideo, estilo: EstiloPunto.cercano, etiqueta: '12'),
          PuntoMapa(id: 'd', coordenadas: _montevideo, estilo: EstiloPunto.seleccionado),
          PuntoMapa(id: 'e', coordenadas: _montevideo, estilo: EstiloPunto.nuevo),
          PuntoMapa(id: 'f', coordenadas: _montevideo, estilo: EstiloPunto.gps),
        ];
        List<String> ids(Map<String, dynamic> geojson) => [
          for (final f in geojson['features'] as List<dynamic>)
            ((f as Map<String, dynamic>)['properties'] as Map<String, dynamic>)['id'] as String,
        ];

        expect(ids(ConstructorEstiloMapa.coleccionPuntos(puntos)), ['a', 'b']);
        expect(ids(ConstructorEstiloMapa.coleccionPuntosLibres(puntos)), ['c', 'd', 'e', 'f']);
        expect(
          {for (final e in EstiloPunto.values) e.name: e.sinAgrupar},
          {
            'contexto': false,
            'candidata': false,
            'cercano': true,
            'seleccionado': true,
            'nuevo': true,
            'gps': true,
          },
        );
      });

      test('el número de puerta viaja como propiedad «etiqueta»', () {
        final geojson = ConstructorEstiloMapa.coleccionPuntosLibres(const [
          PuntoMapa(
            id: 'c',
            coordenadas: _montevideo,
            estilo: EstiloPunto.cercano,
            etiqueta: '1250',
          ),
        ]);

        final f = (geojson['features'] as List<dynamic>).single as Map<String, dynamic>;
        expect(f['properties'], {'id': 'c', 'estilo': 'cercano', 'etiqueta': '1250'});
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

      test('el grupo es el círculo oscuro del canvas: borde blanco, cuenta en blanco, y más '
          'grande desde 100', () {
        final estilo = construir(_config(agrupar: true));

        final paint =
            capa(estilo, ConstructorEstiloMapa.capaGrupos)['paint'] as Map<String, dynamic>;
        expect(paint['circle-color'], '#0E1A2B');
        expect(paint['circle-stroke-color'], '#FFFFFF');
        expect(paint['circle-stroke-width'], 2);
        expect(paint['circle-radius'], [
          'step',
          ['get', 'point_count'],
          ConstructorEstiloMapa.radioGrupo,
          100,
          ConstructorEstiloMapa.radioGrupoGrande,
        ]);
        expect(ConstructorEstiloMapa.radioGrupo * 2, 34, reason: 'los 34 px del canvas');
        final cuenta = capa(estilo, 'colportores:grupos-cuenta')['paint'] as Map<String, dynamic>;
        expect(cuenta['text-color'], '#FFFFFF');
        expect(capa(estilo, 'colportores:grupos-halo')['filter'], ['has', 'point_count']);
      });

      test('el cercano es un círculo blanco con el número de la puerta adentro, que crece con '
          'los caracteres', () {
        final estilo = construir(_config());

        final paint =
            capa(estilo, ConstructorEstiloMapa.capaCercano)['paint'] as Map<String, dynamic>;
        expect(paint['circle-color'], '#FFFFFF');
        expect(paint['circle-stroke-color'], '#6B7688');
        expect(paint['circle-radius'], [
          'step',
          [
            'length',
            [
              'to-string',
              ['get', 'etiqueta'],
            ],
          ],
          ConstructorEstiloMapa.radioEtiqueta,
          5,
          ConstructorEstiloMapa.radioEtiquetaLarga,
          6,
          ConstructorEstiloMapa.radioEtiquetaMuyLarga,
        ]);
        final numero = capa(estilo, 'colportores:cercano-numero');
        expect(numero['type'], 'symbol');
        expect((numero['layout'] as Map<String, dynamic>)['text-field'], ['get', 'etiqueta']);
        expect(numero['filter'], contains(equals(['has', 'etiqueta'])));
      });

      test('el seleccionado lleva un aro doble, blanco y azul, debajo del marcador', () {
        final estilo = construir(_config());
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        final aro = capa(estilo, 'colportores:seleccionado-aro')['paint'] as Map<String, dynamic>;
        expect(aro['circle-color'], '#002856');
        final blanco =
            capa(estilo, 'colportores:seleccionado-aro-blanco')['paint'] as Map<String, dynamic>;
        expect(blanco['circle-color'], '#FFFFFF');
        expect(
          ids.indexOf('colportores:seleccionado-aro'),
          lessThan(ids.indexOf('colportores:seleccionado-aro-blanco')),
        );
        expect(
          ids.indexOf('colportores:seleccionado-aro-blanco'),
          lessThan(ids.indexOf(ConstructorEstiloMapa.capaSeleccionado)),
        );
        expect(capa(estilo, 'colportores:seleccionado-numero')['type'], 'symbol');
      });

      test('sin los recursos el cercano y el seleccionado siguen, sin el número', () {
        final estilo = construirSinRecursos(_config());
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        expect(ids, contains(ConstructorEstiloMapa.capaCercano));
        expect(ids, contains(ConstructorEstiloMapa.capaSeleccionado));
        expect(ids, isNot(contains('colportores:cercano-numero')));
        expect(ids, isNot(contains('colportores:seleccionado-numero')));
      });

      test('el seleccionado y el cercano responden al toque', () {
        expect(
          ConstructorEstiloMapa.capasTocables,
          containsAll([ConstructorEstiloMapa.capaCercano, ConstructorEstiloMapa.capaSeleccionado]),
        );
      });

      test('la letra de la candidata solo se dibuja si la tiene', () {
        final letra = capa(construir(_config()), 'colportores:candidata-letra');

        expect(letra['filter'], contains(equals(['has', 'letra'])));
        expect((letra['layout'] as Map<String, dynamic>)['text-field'], ['get', 'letra']);
      });

      test('el círculo de la candidata crece cuando la letra tiene dos caracteres (AA, AB…)', () {
        final paint =
            capa(construir(_config()), ConstructorEstiloMapa.capaCandidata)['paint']
                as Map<String, dynamic>;

        expect(paint['circle-radius'], [
          'case',
          [
            '>',
            [
              'length',
              [
                'to-string',
                ['get', 'letra'],
              ],
            ],
            1,
          ],
          ConstructorEstiloMapa.radioCandidataDosLetras,
          ConstructorEstiloMapa.radioCandidata,
        ]);
        expect(
          ConstructorEstiloMapa.radioCandidataDosLetras,
          greaterThan(ConstructorEstiloMapa.radioCandidata),
        );
        expect(ConstructorEstiloMapa.radioCandidata, 11.5, reason: 'el de una letra no cambia');
      });

      test('el punto nuevo toma el color primario del tema', () {
        final estilo = construir(_config(colorNuevo: const Color(0xFF123456)));

        final paint =
            capa(estilo, ConstructorEstiloMapa.capaNuevo)['paint'] as Map<String, dynamic>;
        expect(paint['circle-color'], '#123456');
      });
    });

    group('área de «cerca tuyo»', () {
      test('sin área la fuente no tiene geometrías', () {
        expect(ConstructorEstiloMapa.poligonoCercania(null)['features'], isEmpty);
      });

      test('un área válida es un polígono de ese radio en metros', () {
        final poligono = ConstructorEstiloMapa.poligonoCercania(
          const CirculoCercania(centro: _montevideo, radioMetros: 60),
        );

        final features = poligono['features'] as List<dynamic>;
        expect(features, hasLength(1));
        final geometria =
            (features.single as Map<String, dynamic>)['geometry'] as Map<String, dynamic>;
        final anillo = ((geometria['coordinates'] as List<dynamic>).single as List<dynamic>)
            .cast<List<dynamic>>();
        for (final v in anillo) {
          final punto = Coordenadas(lat: v[1] as double, lon: v[0] as double);
          expect(_montevideo.distanciaMetrosA(punto), closeTo(60, 0.2));
        }
      });

      test('se dibuja punteada y suave, debajo de los puntos', () {
        final estilo = construir(
          _config(cercania: const CirculoCercania(centro: _montevideo, radioMetros: 60)),
        );
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        final borde = capa(estilo, 'colportores:cercania-borde')['paint'] as Map<String, dynamic>;
        expect(borde['line-dasharray'], isNotEmpty);
        expect(capa(estilo, 'colportores:cercania-relleno')['type'], 'fill');
        expect(
          ids.indexOf('colportores:cercania-borde'),
          lessThan(ids.indexOf(ConstructorEstiloMapa.capaContexto)),
        );
        final fuentes = estilo['sources'] as Map<String, dynamic>;
        final fuente = fuentes[ConstructorEstiloMapa.fuenteCercania] as Map<String, dynamic>;
        expect(
          ((fuente['data'] as Map<String, dynamic>)['features'] as List<dynamic>),
          hasLength(1),
        );
      });

      test('se arma también sin los recursos (es una línea y un relleno, sin patrón)', () {
        final estilo = construirSinRecursos(
          _config(cercania: const CirculoCercania(centro: _montevideo, radioMetros: 60)),
        );
        final ids = [for (final c in capas(estilo)) c['id'] as String];

        expect(ids, contains('colportores:cercania-borde'));
        expect(ids, contains('colportores:cercania-relleno'));
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
