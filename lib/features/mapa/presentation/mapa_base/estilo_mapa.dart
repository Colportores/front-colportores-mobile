import 'dart:convert';

import 'package:flutter/painting.dart';

import '../../domain/services/circulo_geografico.dart';
import '../../domain/value_objects/coordenadas.dart';
import 'marcador_cercano.dart';
import 'modelo_mapa_base.dart';

/// Arma el estilo MapLibre que dibuja `MapaBase`: el de backend (`estilo/colportores.json`, con la
/// paleta del canvas) apuntando al PMTiles que corresponda y a los glyphs y sprites de la app, más
/// las capas propias de la app (puntos, grupos, radio de precisión y área de «cerca tuyo»).
///
/// Es todo JSON puro: se prueba sin la vista nativa.
abstract final class ConstructorEstiloMapa {
  /// La fuente de tiles del estilo de backend, con `url: "pmtiles://REEMPLAZAR"`.
  static const fuenteTiles = 'protomaps';

  /// Los puntos (con grupos si se pidieron), los que nunca se agrupan (el GPS, el punto nuevo, el
  /// seleccionado y los cercanos: [EstiloPunto.sinAgrupar]), el radio de precisión del GPS y el
  /// área de «cerca tuyo».
  static const fuentePuntos = 'colportores-puntos';
  static const fuentePuntosLibres = 'colportores-puntos-libres';
  static const fuentePrecision = 'colportores-precision';
  static const fuenteCercania = 'colportores-cercania';

  static const capaGrupos = 'colportores:grupos';
  static const capaContexto = 'colportores:contexto';
  static const capaCandidata = 'colportores:candidata';

  /// «Cerca tuyo»: la etiqueta con el número de puerta (capa de símbolos, una imagen por número que
  /// la vista registra: [MarcadorCercano]) y, para el punto cuya imagen no se pudo registrar, el
  /// círculo con el número de respaldo.
  static const capaCercano = 'colportores:cercano';
  static const capaCercanoRespaldo = 'colportores:cercano-respaldo';
  static const capaSeleccionado = 'colportores:seleccionado';
  static const capaNuevo = 'colportores:nuevo';
  static const capaGps = 'colportores:gps';

  /// El radio del círculo de una candidata (en px): con una letra y con dos («AA», «AB»…).
  static const radioCandidata = 11.5;
  static const radioCandidataDosLetras = 14.5;

  /// El radio del grupo de ubicaciones (en px): hasta 99 y de 100 en adelante.
  static const radioGrupo = 17.0;
  static const radioGrupoGrande = 21.0;

  /// El radio del círculo de un punto con número de puerta (en px): hasta 4 caracteres («1250»),
  /// con 5 («1250A») y con 6 o más.
  static const radioEtiqueta = 16.0;
  static const radioEtiquetaLarga = 19.0;
  static const radioEtiquetaMuyLarga = 22.0;

  /// Las capas que responden al toque de un punto o un grupo.
  static const capasTocables = [
    capaGrupos,
    capaSeleccionado,
    capaCercano,
    capaCercanoRespaldo,
    capaContexto,
    capaCandidata,
    capaNuevo,
    capaGps,
  ];

  /// Las que cuentan para un toque largo: las mismas menos «Tu ubicación», que no tiene acción. A
  /// zoom de calle el colportor suele estar parado a pocos metros de la casa que quiere registrar:
  /// apoyar el dedo sobre su propio punto azul tiene que abrir el alta, no quedar en silencio.
  static const capasTocablesLargo = [
    capaGrupos,
    capaSeleccionado,
    capaCercano,
    capaCercanoRespaldo,
    capaContexto,
    capaCandidata,
    capaNuevo,
  ];

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

    var capas = <Map<String, dynamic>>[
      for (final capa in estilo['layers'] as List<dynamic>)
        if (conRecursos || !_usaRecursos(capa as Map<String, dynamic>))
          capa as Map<String, dynamic>,
    ];
    final fuentes = Map<String, dynamic>.from(estilo['sources'] as Map<String, dynamic>);

    final urlsTiles = config.fuente.urlsPmtiles;
    if (urlsTiles.isEmpty) {
      // Sin tiles queda el fondo: ninguna capa del estilo de backend tiene de dónde leer.
      fuentes.remove(fuenteTiles);
      capas.removeWhere((c) => c['source'] == fuenteTiles);
    } else {
      final tiles = Map<String, dynamic>.from(fuentes[fuenteTiles] as Map<String, dynamic>);
      tiles['url'] = urlsTiles.first;
      fuentes[fuenteTiles] = tiles;
      if (urlsTiles.length > 1) {
        // Un paquete en varias partes: una fuente por parte y las capas de los tiles repetidas
        // para cada una, en el mismo orden de apilado (capa por capa, no parte por parte).
        for (var i = 1; i < urlsTiles.length; i++) {
          fuentes[_fuenteDeParte(i)] = {...tiles, 'url': urlsTiles[i]};
        }
        capas = [
          for (final capa in capas)
            if (capa['source'] == fuenteTiles)
              for (var i = 0; i < urlsTiles.length; i++) _capaDeParte(capa, i)
            else
              capa,
        ];
      }
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
    fuentes[fuentePuntosLibres] = {'type': 'geojson', 'data': coleccionPuntosLibres(config.puntos)};
    fuentes[fuentePrecision] = {'type': 'geojson', 'data': poligonoPrecision(config.precision)};
    fuentes[fuenteCercania] = {'type': 'geojson', 'data': poligonoCercania(config.cercania)};

    estilo['sources'] = fuentes;
    estilo['layers'] = [...capas, ..._capasPropias(config, conRecursos: conRecursos)];
    return jsonEncode(estilo);
  }

  /// El nombre de la fuente de la parte [indice] (0 es la primera: [fuenteTiles]).
  static String _fuenteDeParte(int indice) =>
      indice == 0 ? fuenteTiles : '$fuenteTiles-p${indice + 1}';

  /// La copia de [capa] para la parte [indice]; la de la primera parte es la capa tal cual.
  static Map<String, dynamic> _capaDeParte(Map<String, dynamic> capa, int indice) {
    if (indice == 0) return capa;
    return {...capa, 'id': '${capa['id']}-p${indice + 1}', 'source': _fuenteDeParte(indice)};
  }

  /// ¿La capa necesita glyphs o sprites? Los textos (`symbol`) y los rellenos y líneas con patrón.
  static bool _usaRecursos(Map<String, dynamic> capa) {
    if (capa['type'] == 'symbol') return true;
    final paint = capa['paint'];
    return paint is Map<String, dynamic> && paint.keys.any((k) => k.endsWith('-pattern'));
  }

  /// Los puntos que se pueden agrupar, como `FeatureCollection` de GeoJSON, con `id`, `estilo`,
  /// `letra` y `etiqueta` como propiedades.
  static Map<String, dynamic> coleccionPuntos(List<PuntoMapa> puntos) =>
      _coleccion(puntos.where((p) => !p.estilo.sinAgrupar));

  /// Los puntos que nunca se agrupan ([EstiloPunto.sinAgrupar]), con las mismas propiedades. Van en
  /// otra fuente: en la de los grupos, un punto del GPS o uno cercano quedaría absorbido por el
  /// grupo de los que tiene al lado.
  ///
  /// [imagenes] son los nombres de las imágenes que la vista ya registró en el estilo
  /// ([MarcadorCercano.nombre]): un punto cercano cuya etiqueta está entre ellas lleva la propiedad
  /// `imagen` y lo dibuja la capa de símbolos; el que no, el círculo de respaldo.
  static Map<String, dynamic> coleccionPuntosLibres(
    List<PuntoMapa> puntos, {
    Set<String> imagenes = const {},
  }) => _coleccion(puntos.where((p) => p.estilo.sinAgrupar), imagenes);

  static Map<String, dynamic> _coleccion(
    Iterable<PuntoMapa> puntos, [
    Set<String> imagenes = const {},
  ]) => {
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
            if (p.etiqueta != null) 'etiqueta': p.etiqueta,
            if (p.estilo == EstiloPunto.cercano &&
                p.etiqueta != null &&
                imagenes.contains(MarcadorCercano.nombre(p.etiqueta!)))
              'imagen': MarcadorCercano.nombre(p.etiqueta!),
          },
        },
    ],
  };

  /// El radio de precisión como `FeatureCollection` con un polígono, o vacía si no hay.
  static Map<String, dynamic> poligonoPrecision(CirculoPrecision? precision) =>
      _poligono(precision?.centro, precision?.radioMetros);

  /// El área de «cerca tuyo» como `FeatureCollection` con un polígono, o vacía si no hay.
  static Map<String, dynamic> poligonoCercania(CirculoCercania? cercania) =>
      _poligono(cercania?.centro, cercania?.radioMetros);

  static Map<String, dynamic> _poligono(Coordenadas? centro, double? radioMetros) {
    final anillo = centro == null || radioMetros == null
        ? const <Coordenadas>[]
        : CirculoGeografico.anillo(centro, radioMetros);
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

  /// El punto cuya etiqueta ya está registrada como imagen en el estilo, y el que no.
  static const List<Object?> _tieneImagen = ['has', 'imagen'];
  static const List<Object?> _sinImagen = [
    '!',
    ['has', 'imagen'],
  ];

  static List<Object?> _filtroEstilo(EstiloPunto estilo) => ['all', _noEsGrupo, _esEstilo(estilo)];

  static List<Object?> _esEstilo(EstiloPunto estilo) => [
    '==',
    ['get', 'estilo'],
    estilo.name,
  ];

  /// El radio de un círculo con número de puerta: crece con la cantidad de caracteres para que
  /// entre. `to-string` deja a los puntos sin número en «» (largo 0).
  static const List<Object?> _radioPorEtiqueta = [
    'step',
    [
      'length',
      [
        'to-string',
        ['get', 'etiqueta'],
      ],
    ],
    radioEtiqueta,
    5,
    radioEtiquetaLarga,
    6,
    radioEtiquetaMuyLarga,
  ];

  static const _estiloNumero = {
    'text-field': ['get', 'etiqueta'],
    'text-font': ['NotoSans-Medium'],
    'text-size': 12,
    'text-allow-overlap': true,
    'text-ignore-placement': true,
  };

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
        'id': 'colportores:cercania-relleno',
        'type': 'fill',
        'source': fuenteCercania,
        'paint': {'fill-color': _hex(ColoresMapa.puntoGps), 'fill-opacity': .06},
      },
      {
        'id': 'colportores:cercania-borde',
        'type': 'line',
        'source': fuenteCercania,
        'paint': {
          'line-color': _hex(ColoresMapa.puntoGps),
          'line-opacity': .55,
          'line-width': 1.5,
          'line-dasharray': [4, 3],
        },
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
        'id': 'colportores:grupos-halo',
        'type': 'circle',
        'source': fuentePuntos,
        'filter': ['has', 'point_count'],
        'paint': {
          'circle-color': _hex(ColoresMapa.tintaOscura),
          'circle-opacity': .18,
          'circle-radius': [
            'step',
            ['get', 'point_count'],
            radioGrupo + 5,
            100,
            radioGrupoGrande + 5,
          ],
        },
      },
      {
        'id': capaGrupos,
        'type': 'circle',
        'source': fuentePuntos,
        'filter': ['has', 'point_count'],
        'paint': {
          'circle-color': _hex(ColoresMapa.tintaOscura),
          'circle-radius': [
            'step',
            ['get', 'point_count'],
            radioGrupo,
            100,
            radioGrupoGrande,
          ],
          'circle-stroke-width': 2,
          'circle-stroke-color': blanco,
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
            'text-size': 13,
            'text-allow-overlap': true,
            'text-ignore-placement': true,
          },
          'paint': {'text-color': blanco},
        },
      {
        'id': capaCandidata,
        'type': 'circle',
        'source': fuentePuntos,
        'filter': _filtroEstilo(EstiloPunto.candidata),
        'paint': {
          'circle-color': blanco,
          // Con dos letras («AA», «AB»…, de la candidata 27 en adelante) el círculo crece para que
          // entren. `to-string` deja la letra de las candidatas sin rótulo en «».
          'circle-radius': [
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
            radioCandidataDosLetras,
            radioCandidata,
          ],
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
      // «Cerca tuyo»: la etiqueta del canvas, una imagen por número de puerta que la vista registra
      // (`MarcadorCercano`). Anclada por la punta de abajo y sin esconderse: son pocas y todas
      // tienen que verse.
      {
        'id': capaCercano,
        'type': 'symbol',
        'source': fuentePuntosLibres,
        'filter': ['all', _esEstilo(EstiloPunto.cercano), _tieneImagen],
        'layout': {
          'icon-image': ['get', 'imagen'],
          'icon-anchor': 'bottom',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
      // El respaldo: mientras la imagen de un número no está registrada (o si no se pudo), el punto
      // no queda sin dibujar.
      {
        'id': capaCercanoRespaldo,
        'type': 'circle',
        'source': fuentePuntosLibres,
        'filter': ['all', _esEstilo(EstiloPunto.cercano), _sinImagen],
        'paint': {
          'circle-color': blanco,
          'circle-radius': _radioPorEtiqueta,
          'circle-stroke-width': 2.5,
          'circle-stroke-color': _hex(ColoresMapa.bordeContexto),
        },
      },
      if (conRecursos)
        {
          'id': 'colportores:cercano-numero',
          'type': 'symbol',
          'source': fuentePuntosLibres,
          'filter': [
            'all',
            _esEstilo(EstiloPunto.cercano),
            _sinImagen,
            ['has', 'etiqueta'],
          ],
          'layout': _estiloNumero,
          'paint': {'text-color': _hex(ColoresMapa.tinta)},
        },
      // El seleccionado: el marcador con un aro doble, blanco y azul, encima de los demás.
      {
        'id': 'colportores:seleccionado-aro',
        'type': 'circle',
        'source': fuentePuntosLibres,
        'filter': _esEstilo(EstiloPunto.seleccionado),
        'paint': {
          'circle-color': _hex(ColoresMapa.aroSeleccion),
          'circle-radius': ['+', _radioPorEtiqueta, 6],
        },
      },
      {
        'id': 'colportores:seleccionado-aro-blanco',
        'type': 'circle',
        'source': fuentePuntosLibres,
        'filter': _esEstilo(EstiloPunto.seleccionado),
        'paint': {
          'circle-color': blanco,
          'circle-radius': ['+', _radioPorEtiqueta, 3],
        },
      },
      {
        'id': capaSeleccionado,
        'type': 'circle',
        'source': fuentePuntosLibres,
        'filter': _esEstilo(EstiloPunto.seleccionado),
        'paint': {
          'circle-color': blanco,
          'circle-radius': _radioPorEtiqueta,
          'circle-stroke-width': 2.5,
          'circle-stroke-color': _hex(ColoresMapa.bordeContexto),
        },
      },
      if (conRecursos)
        {
          'id': 'colportores:seleccionado-numero',
          'type': 'symbol',
          'source': fuentePuntosLibres,
          'filter': [
            'all',
            _esEstilo(EstiloPunto.seleccionado),
            ['has', 'etiqueta'],
          ],
          'layout': _estiloNumero,
          'paint': {'text-color': _hex(ColoresMapa.tinta)},
        },
      {
        'id': capaNuevo,
        'type': 'circle',
        'source': fuentePuntosLibres,
        'filter': _esEstilo(EstiloPunto.nuevo),
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
        'source': fuentePuntosLibres,
        'filter': _esEstilo(EstiloPunto.gps),
        'paint': {
          'circle-color': _hex(ColoresMapa.puntoGps),
          'circle-opacity': .16,
          'circle-radius': 17,
        },
      },
      {
        'id': capaGps,
        'type': 'circle',
        'source': fuentePuntosLibres,
        'filter': _esEstilo(EstiloPunto.gps),
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
