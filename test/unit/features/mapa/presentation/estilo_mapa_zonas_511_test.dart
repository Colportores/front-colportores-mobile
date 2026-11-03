// Las zonas en el estilo del mapa (#511): van por debajo de las casas, no reciben toques, la propia se
// resalta y todo lo que depende del color tiene otra señal.
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/estilo_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/zonas_mapa.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _montevideo = Coordenadas(lat: -34.88761, lon: -56.13024);
const _recursos = '/data/user/0/uy.colportores/files/mapa/basemaps-5.7.2-1';

List<List<Coordenadas>> _cuadrado(double lat, double lon, double lado) => [
  [
    Coordenadas(lat: lat, lon: lon),
    Coordenadas(lat: lat, lon: lon + lado),
    Coordenadas(lat: lat + lado, lon: lon + lado),
    Coordenadas(lat: lat + lado, lon: lon),
    Coordenadas(lat: lat, lon: lon),
  ],
];

ZonaMapa _zona(
  String id, {
  bool propia = false,
  Color color = const Color(0xFF1F6E3A),
  Coordenadas? rotulo = _montevideo,
  List<List<List<Coordenadas>>>? poligonos,
}) => ZonaMapa(
  id: id,
  rotulo: propia ? 'Tu zona · $id' : id,
  poligonos: poligonos ?? [_cuadrado(-34.9, -56.2, .05)],
  color: color,
  propia: propia,
  puntoRotulo: rotulo,
);

ConfigVistaMapa _config({
  List<ZonaMapa> zonas = const [],
  List<PuntoMapa> puntos = const [],
  bool agrupar = true,
}) => ConfigVistaMapa(
  fuente: const FuenteMapa.online('https://s/uy.pmtiles'),
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
  zonas: zonas,
);

void main() {
  late String estiloBase;

  setUpAll(() => estiloBase = File('assets/mapa/estilo/colportores.json').readAsStringSync());

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

  List<String> ids(Map<String, dynamic> estilo) => [
    for (final c in capas(estilo)) c['id'] as String,
  ];

  Map<String, dynamic> capa(Map<String, dynamic> estilo, String id) =>
      capas(estilo).singleWhere((c) => c['id'] == id);

  Map<String, dynamic> datos(Map<String, dynamic> estilo, String fuente) =>
      ((estilo['sources'] as Map<String, dynamic>)[fuente] as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

  List<Map<String, dynamic>> features(Map<String, dynamic> geojson) => [
    for (final f in geojson['features'] as List<dynamic>) f as Map<String, dynamic>,
  ];

  const capasDeZonas = [
    ConstructorEstiloMapa.capaZonasOtrasRelleno,
    ConstructorEstiloMapa.capaZonasOtrasBorde,
    ConstructorEstiloMapa.capaZonaPropiaHalo,
    ConstructorEstiloMapa.capaZonaPropiaRelleno,
    ConstructorEstiloMapa.capaZonaPropiaBorde,
  ];

  group('sin zonas', () {
    test('las fuentes existen y están vacías: no se dibuja nada', () {
      final estilo = construir(_config());

      expect(features(datos(estilo, ConstructorEstiloMapa.fuenteZonas)), isEmpty);
      expect(features(datos(estilo, ConstructorEstiloMapa.fuenteZonasRotulos)), isEmpty);
    });
  });

  group('las capas', () {
    test('van por debajo de todas las del colportor, y por encima del mapa base', () {
      final estilo = construir(_config(zonas: [_zona('a', propia: true), _zona('b')]));
      final todas = ids(estilo);
      final primeraPropia = todas.indexWhere((id) => id.startsWith('colportores:'));

      expect(todas.sublist(primeraPropia, primeraPropia + capasDeZonas.length), capasDeZonas);
      final ultimaDeZonas = todas.indexOf(ConstructorEstiloMapa.capaZonasRotulo);
      for (final id in todas.skip(ultimaDeZonas + 1)) {
        expect(id, startsWith('colportores:'));
        expect(id, isNot(contains('zonas')));
      }
      // Todos los puntos —casas, grupos, el aviso del GPS— quedan arriba.
      for (final arriba in [
        ConstructorEstiloMapa.capaContexto,
        ConstructorEstiloMapa.capaEstado,
        ConstructorEstiloMapa.capaGrupos,
        ConstructorEstiloMapa.capaCercano,
        ConstructorEstiloMapa.capaSeleccionado,
        ConstructorEstiloMapa.capaCuadrado,
        ConstructorEstiloMapa.capaNuevo,
        ConstructorEstiloMapa.capaGps,
        'colportores:precision-relleno',
        'colportores:cercania-borde',
      ]) {
        expect(todas.indexOf(arriba), greaterThan(ultimaDeZonas), reason: arriba);
      }
    });

    test('ninguna es tocable: el toque sigue siendo de las casas y de los grupos', () {
      for (final id in [...capasDeZonas, ConstructorEstiloMapa.capaZonasRotulo]) {
        expect(ConstructorEstiloMapa.capasTocables, isNot(contains(id)), reason: id);
        expect(ConstructorEstiloMapa.capasTocablesLargo, isNot(contains(id)), reason: id);
      }
    });

    test('ids únicos y cada capa lee de una fuente que existe', () {
      final estilo = construir(_config(zonas: [_zona('a')]));
      final fuentes = (estilo['sources'] as Map<String, dynamic>).keys.toSet();

      expect(ids(estilo).toSet(), hasLength(ids(estilo).length));
      for (final c in capas(estilo)) {
        if (c['type'] == 'background') continue;
        expect(fuentes, contains(c['source']), reason: c['id'] as String);
      }
    });

    test('la propia se separa de las demás por un filtro sobre la propiedad `propia`', () {
      final estilo = construir(_config(zonas: [_zona('a', propia: true), _zona('b')]));

      for (final id in [
        ConstructorEstiloMapa.capaZonaPropiaHalo,
        ConstructorEstiloMapa.capaZonaPropiaRelleno,
        ConstructorEstiloMapa.capaZonaPropiaBorde,
      ]) {
        expect(capa(estilo, id)['filter'], [
          '==',
          ['get', 'propia'],
          true,
        ]);
      }
      for (final id in [
        ConstructorEstiloMapa.capaZonasOtrasRelleno,
        ConstructorEstiloMapa.capaZonasOtrasBorde,
      ]) {
        expect(capa(estilo, id)['filter'], [
          '==',
          ['get', 'propia'],
          false,
        ]);
      }
    });
  });

  group('la zona propia resaltada y las demás tenues', () {
    test('el borde de la propia es más grueso y más firme que el de las demás', () {
      final estilo = construir(_config(zonas: [_zona('a', propia: true), _zona('b')]));
      final propia = capa(estilo, ConstructorEstiloMapa.capaZonaPropiaBorde)['paint'] as Map;
      final otra = capa(estilo, ConstructorEstiloMapa.capaZonasOtrasBorde)['paint'] as Map;

      expect(propia['line-width'] as num, greaterThan((otra['line-width'] as num) * 1.5));
      expect(propia.containsKey('line-opacity'), isFalse, reason: 'la propia es opaca');
      expect(otra['line-opacity'] as num, lessThan(.5));
    });

    test('el relleno de la propia es más firme que el de las demás, que es casi nada', () {
      final estilo = construir(_config(zonas: [_zona('a', propia: true), _zona('b')]));
      final propia = capa(estilo, ConstructorEstiloMapa.capaZonaPropiaRelleno)['paint'] as Map;
      final otra = capa(estilo, ConstructorEstiloMapa.capaZonasOtrasRelleno)['paint'] as Map;

      expect(propia['fill-opacity'] as num, greaterThan(otra['fill-opacity'] as num));
      expect(otra['fill-opacity'] as num, lessThanOrEqualTo(.12));
    });

    test(
      'el borde de la propia lleva un filete blanco más ancho por debajo (AA sobre cualquier fondo)',
      () {
        final estilo = construir(_config(zonas: [_zona('a', propia: true)]));
        final todas = ids(estilo);
        final halo = capa(estilo, ConstructorEstiloMapa.capaZonaPropiaHalo)['paint'] as Map;
        final borde = capa(estilo, ConstructorEstiloMapa.capaZonaPropiaBorde)['paint'] as Map;

        expect(halo['line-color'], '#FFFFFF');
        expect(halo['line-width'] as num, greaterThan(borde['line-width'] as num));
        expect(
          todas.indexOf(ConstructorEstiloMapa.capaZonaPropiaHalo),
          lessThan(todas.indexOf(ConstructorEstiloMapa.capaZonaPropiaBorde)),
        );
      },
    );

    test('la propia se dibuja arriba de las demás', () {
      final todas = ids(construir(_config(zonas: [_zona('a', propia: true), _zona('b')])));

      for (final otra in [
        ConstructorEstiloMapa.capaZonasOtrasRelleno,
        ConstructorEstiloMapa.capaZonasOtrasBorde,
      ]) {
        expect(
          todas.indexOf(otra),
          lessThan(todas.indexOf(ConstructorEstiloMapa.capaZonaPropiaHalo)),
        );
      }
    });

    test('el color de cada zona viaja en la propiedad `color`, ya con contraste', () {
      final amarillo = ColoresZona.borde('#FFD966');
      final estilo = construir(_config(zonas: [_zona('a', color: amarillo)]));
      final colorGeojson =
          (features(datos(estilo, ConstructorEstiloMapa.fuenteZonas)).single['properties']
                  as Map)['color']
              as String;
      final r = int.parse(colorGeojson.substring(1, 3), radix: 16);
      final g = int.parse(colorGeojson.substring(3, 5), radix: 16);
      final b = int.parse(colorGeojson.substring(5, 7), radix: 16);

      expect(Color.fromARGB(255, r, g, b), amarillo);
      expect(ColoresZona.contraste(Color.fromARGB(255, r, g, b)), greaterThanOrEqualTo(3));
      for (final id in [
        ConstructorEstiloMapa.capaZonaPropiaBorde,
        ConstructorEstiloMapa.capaZonasOtrasBorde,
      ]) {
        expect((capa(estilo, id)['paint'] as Map)['line-color'], ['get', 'color']);
      }
    });
  });

  group('el nombre (la señal que no depende del color)', () {
    test('es una capa de símbolos sobre la fuente de nombres, con tipografía de la app', () {
      final estilo = construir(_config(zonas: [_zona('a', propia: true)]));
      final rotulo = capa(estilo, ConstructorEstiloMapa.capaZonasRotulo);
      final layout = rotulo['layout'] as Map<String, dynamic>;

      expect(rotulo['type'], 'symbol');
      expect(rotulo['source'], ConstructorEstiloMapa.fuenteZonasRotulos);
      expect(layout['text-field'], ['get', 'rotulo']);
      for (final fuente in layout['text-font'] as List<dynamic>) {
        expect(Directory('assets/mapa/glyphs/$fuente').existsSync(), isTrue);
      }
    });

    test('la propia se acomoda primero (gana si dos nombres se pisan)', () {
      final layout =
          capa(construir(_config()), ConstructorEstiloMapa.capaZonasRotulo)['layout'] as Map;

      expect(layout['symbol-sort-key'], [
        'case',
        [
          '==',
          ['get', 'propia'],
          true,
        ],
        0,
        1,
      ]);
    });

    test('sin glyphs ni sprites no hay capa de nombres, y las zonas se ven igual', () {
      final estilo = construirSinRecursos(_config(zonas: [_zona('a', propia: true)]));

      expect(ids(estilo), isNot(contains(ConstructorEstiloMapa.capaZonasRotulo)));
      expect(ids(estilo), containsAll(capasDeZonas));
      for (final c in capas(estilo)) {
        if (c['type'] == 'symbol') {
          expect(
            (c['layout'] as Map).containsKey('text-field'),
            isFalse,
            reason: c['id'] as String,
          );
        }
      }
    });

    test('un punto por zona, con su nombre; sin punto de nombre, ninguno', () {
      final estilo = construir(
        _config(zonas: [_zona('a', propia: true), _zona('b', rotulo: null)]),
      );

      final puntos = features(datos(estilo, ConstructorEstiloMapa.fuenteZonasRotulos));
      expect(puntos, hasLength(1));
      expect(puntos.single['properties'], {'id': 'a', 'propia': true, 'rotulo': 'Tu zona · a'});
      expect((puntos.single['geometry'] as Map)['coordinates'], [_montevideo.lon, _montevideo.lat]);
    });
  });

  group('los polígonos', () {
    test('cada zona es un Polygon con [lon, lat] y sus propiedades', () {
      final estilo = construir(_config(zonas: [_zona('a', propia: true)]));

      final f = features(datos(estilo, ConstructorEstiloMapa.fuenteZonas)).single;
      final geometria = f['geometry'] as Map<String, dynamic>;
      expect(geometria['type'], 'Polygon');
      final anillo = ((geometria['coordinates'] as List).single as List).cast<List<dynamic>>();
      expect(anillo.first, [-56.2, -34.9]);
      expect(anillo.first, anillo.last, reason: 'el anillo viene cerrado');
      expect(f['properties'], {'id': 'a', 'propia': true, 'color': '#1F6E3A'});
    });

    test('una zona de varios polígonos sale como una feature por polígono', () {
      final estilo = construir(
        _config(
          zonas: [
            _zona('a', poligonos: [_cuadrado(-34.9, -56.2, .01), _cuadrado(-34.8, -56.1, .01)]),
          ],
        ),
      );

      final fs = features(datos(estilo, ConstructorEstiloMapa.fuenteZonas));
      expect(fs, hasLength(2));
      expect({for (final f in fs) (f['properties'] as Map)['id']}, {'a'});
    });

    test('un polígono con hueco lo lleva como segundo anillo', () {
      final estilo = construir(
        _config(
          zonas: [
            _zona(
              'a',
              poligonos: [
                [..._cuadrado(-34.9, -56.2, .05), ..._cuadrado(-34.89, -56.19, .01)],
              ],
            ),
          ],
        ),
      );

      final f = features(datos(estilo, ConstructorEstiloMapa.fuenteZonas)).single;
      expect(((f['geometry'] as Map)['coordinates'] as List), hasLength(2));
    });

    test('superpuestas: las dos salen, y la propia no depende del orden', () {
      for (final zonas in [
        [_zona('a'), _zona('b', propia: true)],
        [_zona('b', propia: true), _zona('a')],
      ]) {
        final fs = features(
          datos(construir(_config(zonas: zonas)), ConstructorEstiloMapa.fuenteZonas),
        );

        expect(fs, hasLength(2));
        expect(
          {for (final f in fs) (f['properties'] as Map)['id']: (f['properties'] as Map)['propia']},
          {'a': false, 'b': true},
        );
      }
    });
  });

  group('junto con las casas', () {
    test('las casas siguen en sus fuentes y las zonas no se mezclan con ellas', () {
      const casas = [
        PuntoMapa(id: 'c1', coordenadas: _montevideo),
        PuntoMapa(id: 'c2', coordenadas: Coordenadas(lat: -34.8877, lon: -56.1303)),
        PuntoMapa(id: 'gps', coordenadas: _montevideo, estilo: EstiloPunto.gps),
      ];
      final estilo = construir(_config(zonas: [_zona('a', propia: true)], puntos: casas));

      expect(
        features(
          datos(estilo, ConstructorEstiloMapa.fuentePuntos),
        ).map((f) => (f['properties'] as Map)['id']),
        ['c1', 'c2'],
      );
      expect(
        features(
          datos(estilo, ConstructorEstiloMapa.fuentePuntosLibres),
        ).map((f) => (f['properties'] as Map)['id']),
        ['gps'],
      );
      // Las casas se siguen agrupando con la misma configuración de siempre.
      final fuente = (estilo['sources'] as Map)[ConstructorEstiloMapa.fuentePuntos] as Map;
      expect(fuente['cluster'], isTrue);
      expect(
        (estilo['sources'] as Map)[ConstructorEstiloMapa.fuenteZonas],
        isNot(contains('cluster')),
      );
    });
  });
}
