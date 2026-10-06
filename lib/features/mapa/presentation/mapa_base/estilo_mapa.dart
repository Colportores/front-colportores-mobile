import 'dart:convert';

import 'package:flutter/painting.dart';

import '../../domain/services/circulo_geografico.dart';
import '../../domain/value_objects/coordenadas.dart';
import 'modelo_mapa_base.dart';

/// Arma el estilo MapLibre que dibuja `MapaBase`: el de backend (`estilo/colportores.json`, con la
/// paleta del canvas) apuntando al PMTiles que corresponda y a los glyphs y sprites de la app, más
/// las capas propias de la app (puntos, grupos y radio de precisión).
///
/// Es todo JSON puro: se prueba sin la vista nativa.
abstract final class ConstructorEstiloMapa {
  /// La fuente de tiles del estilo de backend, con `url: "pmtiles://REEMPLAZAR"`.
  static const fuenteTiles = 'protomaps';

  /// Los puntos (con grupos si se pidieron) y el radio de precisión del GPS.
  static const fuentePuntos = 'colportores-puntos';
  static const fuentePrecision = 'colportores-precision';

  static const capaGrupos = 'colportores:grupos';
  static const capaContexto = 'colportores:contexto';
  static const capaCandidata = 'colportores:candidata';
  static const capaNuevo = 'colportores:nuevo';
  static const capaGps = 'colportores:gps';

  /// Las capas que responden al toque de un punto o un grupo.
  static const capasTocables = [capaGrupos, capaContexto, capaCandidata, capaNuevo, capaGps];

  /// El estilo final como texto, para `MapLibreMap.styleString`.
  ///
  /// [directorioRecursos] es donde `PreparadorRecursosMapa` dejó los glyphs y sprites; [estiloBase]
  /// es el JSON de backend tal como se empaqueta.
  static String construir({
    required String estiloBase,
    required String directorioRecursos,
    required ConfigVistaMapa config,
  }) => _armar(estiloBase: estiloBase, directorioRecursos: directorioRecursos, config: config);

  /// El estilo cuando no se pudieron copiar los glyphs y sprites (disco lleno, por ejemplo): sin
  /// tipografías ni íconos, o sea sin las capas que los usan (nombres de calles, números de los
  /// grupos y letras de las candidatas). Lo demás se ve igual: los tiles, los puntos y el radio del
  /// GPS, que son círculos y polígonos. Así el mapa responde y se puede marcar el punto.
  static String construirSinRecursos({
    required String estiloBase,
    required ConfigVistaMapa config,
  }) => _armar(estiloBase: estiloBase, directorioRecursos: null, config: config);

  static String _armar({
    required String estiloBase,
    required String? directorioRecursos,
    required ConfigVistaMapa config,
  }) {
    final conRecursos = directorioRecursos != null;
    final estilo = Map<String, dynamic>.from(jsonDecode(estiloBase) as Map<String, dynamic>);
    if (conRecursos) {
      estilo['glyphs'] = 'file://$directorioRecursos/glyphs/{fontstack}/{range}.pbf';
      estilo['sprite'] = 'file://$directorioRecursos/sprites/grayscale';
    } else {
      estilo.remove('glyphs');
      estilo.remove('sprite');
    }

    final capas = <Map<String, dynamic>>[
      for (final capa in estilo['layers'] as List<dynamic>)
        if (conRecursos || !_usaRecursos(capa as Map<String, dynamic>))
          capa as Map<String, dynamic>,
    ];
    final fuentes = Map<String, dynamic>.from(estilo['sources'] as Map<String, dynamic>);

    final urlTiles = config.fuente.urlPmtiles;
    if (urlTiles == null) {
      // Sin tiles queda el fondo: ninguna capa del estilo de backend tiene de dónde leer.
      fuentes.remove(fuenteTiles);
      capas.removeWhere((c) => c['source'] == fuenteTiles);
    } else {
      final tiles = Map<String, dynamic>.from(fuentes[fuenteTiles] as Map<String, dynamic>);
      tiles['url'] = urlTiles;
      fuentes[fuenteTiles] = tiles;
    }

    for (final capa in capas) {
      if (capa['type'] == 'background') {
        capa['paint'] = {'background-color': _hex(config.fondo)};
      }
    }

    fuentes[fuentePuntos] = {
      'type': 'geojson',
      'data': coleccionPuntos(config.puntos),
      if (config.agruparPuntos) ...{'cluster': true, 'clusterRadius': 44, 'clusterMaxZoom': 17},
    };
    fuentes[fuentePrecision] = {'type': 'geojson', 'data': poligonoPrecision(config.precision)};

    estilo['sources'] = fuentes;
    estilo['layers'] = [...capas, ..._capasPropias(config, conRecursos: conRecursos)];
    return jsonEncode(estilo);
  }

  /// ¿La capa necesita glyphs o sprites? Los textos (`symbol`) y los rellenos y líneas con patrón.
  static bool _usaRecursos(Map<String, dynamic> capa) {
    if (capa['type'] == 'symbol') return true;
    final paint = capa['paint'];
    return paint is Map<String, dynamic> && paint.keys.any((k) => k.endsWith('-pattern'));
  }

  /// Los puntos como `FeatureCollection` de GeoJSON, con `id`, `estilo` y `letra` como propiedades.
  static Map<String, dynamic> coleccionPuntos(List<PuntoMapa> puntos) => {
    'type': 'FeatureCollection',
    'features': [
      for (final p in puntos)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [p.coordenadas.lon, p.coordenadas.lat],
          },
          'properties': {
            'id': p.id,
            'estilo': p.estilo.name,
            if (p.letra != null) 'letra': p.letra,
          },
        },
    ],
  };

  /// El radio de precisión como `FeatureCollection` con un polígono, o vacía si no hay.
  static Map<String, dynamic> poligonoPrecision(CirculoPrecision? precision) {
    final anillo = precision == null
        ? const <Coordenadas>[]
        : CirculoGeografico.anillo(precision.centro, precision.radioMetros);
    return {
      'type': 'FeatureCollection',
      'features': [
        if (anillo.isNotEmpty)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  for (final v in anillo) [v.lon, v.lat],
                ],
              ],
            },
            'properties': const <String, dynamic>{},
          },
      ],
    };
  }

  static const List<Object?> _noEsGrupo = [
    '!',
    ['has', 'point_count'],
  ];

  static List<Object?> _filtroEstilo(EstiloPunto estilo) => [
    'all',
    _noEsGrupo,
    [
      '==',
      ['get', 'estilo'],
      estilo.name,
    ],
  ];

  static List<Map<String, dynamic>> _capasPropias(
    ConfigVistaMapa config, {
    required bool conRecursos,
  }) {
    final blanco = _hex(const Color(0xFFFFFFFF));
    return [
      {
        'id': 'colportores:precision-relleno',
        'type': 'fill',
        'source': fuentePrecision,
        'paint': {'fill-color': _hex(ColoresMapa.puntoGps), 'fill-opacity': .14},
      },
      {
        'id': 'colportores:precision-borde',
        'type': 'line',
        'source': fuentePrecision,
        'paint': {'line-color': _hex(ColoresMapa.puntoGps), 'line-opacity': .45, 'line-width': 1.5},
      },
      {
        'id': 'colportores:contexto-sombra',
        'type': 'circle',
        'source': fuentePuntos,
        'filter': _filtroEstilo(EstiloPunto.contexto),
        'paint': {
          'circle-color': '#000000',
          'circle-opacity': .4,
          'circle-radius': 12,
          'circle-blur': .25,
          'circle-translate': [0, 1],
        },
      },
      {
        'id': capaContexto,
        'type': 'circle',
        'source': fuentePuntos,
        'filter': _filtroEstilo(EstiloPunto.contexto),
        'paint': {
          'circle-color': blanco,
          'circle-radius': 9.5,
          'circle-stroke-width': 2.5,
          'circle-stroke-color': _hex(ColoresMapa.bordeContexto),
        },
      },
      {
        'id': capaGrupos,
        'type': 'circle',
        'source': fuentePuntos,
        'filter': ['has', 'point_count'],
        'paint': {
          'circle-color': blanco,
          'circle-radius': [
            'step',
            ['get', 'point_count'],
            14,
            10,
            18,
            50,
            24,
          ],
          'circle-stroke-width': 2.5,
          'circle-stroke-color': _hex(ColoresMapa.bordeContexto),
        },
      },
      if (conRecursos)
        {
          'id': 'colportores:grupos-cuenta',
          'type': 'symbol',
          'source': fuentePuntos,
          'filter': ['has', 'point_count'],
          'layout': {
            'text-field': ['get', 'point_count_abbreviated'],
            'text-font': ['NotoSans-Medium'],
            'text-size': 12,
            'text-allow-overlap': true,
            'text-ignore-placement': true,
          },
          'paint': {'text-color': _hex(ColoresMapa.tinta)},
        },
      {
        'id': capaCandidata,
        'type': 'circle',
        'source': fuentePuntos,
        'filter': _filtroEstilo(EstiloPunto.candidata),
        'paint': {
          'circle-color': blanco,
          'circle-radius': 11.5,
          'circle-stroke-width': 2.5,
          'circle-stroke-color': _hex(ColoresMapa.bordeCandidata),
        },
      },
      if (conRecursos)
        {
          'id': 'colportores:candidata-letra',
          'type': 'symbol',
          'source': fuentePuntos,
          'filter': [
            'all',
            _filtroEstilo(EstiloPunto.candidata),
            ['has', 'letra'],
          ],
          'layout': {
            'text-field': ['get', 'letra'],
            'text-font': ['NotoSans-Medium'],
            'text-size': 12,
            'text-allow-overlap': true,
            'text-ignore-placement': true,
          },
          'paint': {'text-color': _hex(ColoresMapa.tinta)},
        },
      {
        'id': capaNuevo,
        'type': 'circle',
        'source': fuentePuntos,
        'filter': _filtroEstilo(EstiloPunto.nuevo),
        'paint': {
          'circle-color': _hex(config.colorNuevo),
          'circle-radius': 11,
          'circle-stroke-width': 3,
          'circle-stroke-color': blanco,
        },
      },
      {
        'id': 'colportores:gps-halo',
        'type': 'circle',
        'source': fuentePuntos,
        'filter': _filtroEstilo(EstiloPunto.gps),
        'paint': {
          'circle-color': _hex(ColoresMapa.puntoGps),
          'circle-opacity': .16,
          'circle-radius': 17,
        },
      },
      {
        'id': capaGps,
        'type': 'circle',
        'source': fuentePuntos,
        'filter': _filtroEstilo(EstiloPunto.gps),
        'paint': {
          'circle-color': _hex(ColoresMapa.puntoGps),
          'circle-radius': 6,
          'circle-stroke-width': 3,
          'circle-stroke-color': blanco,
        },
      },
    ];
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
