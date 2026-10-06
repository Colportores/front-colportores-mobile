import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../../../core/logging/app_logger.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import 'estilo_mapa.dart';
import 'modelo_mapa_base.dart';
import 'recursos_mapa_providers.dart';

/// La vista nativa de `MapaBase`: MapLibre Native (Android e iOS) con el estilo de
/// [ConstructorEstiloMapa]. Es la implementación por defecto de [ConstructorVistaMapa].
Widget construirVistaMapLibre(
  BuildContext context,
  ConfigVistaMapa config,
  EventosVistaMapa eventos,
) => VistaMapLibre(config: config, eventos: eventos);

class VistaMapLibre extends ConsumerStatefulWidget {
  const VistaMapLibre({super.key, required this.config, required this.eventos});

  final ConfigVistaMapa config;
  final EventosVistaMapa eventos;

  @override
  ConsumerState<VistaMapLibre> createState() => _VistaMapLibreState();
}

class _VistaMapLibreState extends ConsumerState<VistaMapLibre> {
  static const _modulo = LogModulo.map;

  ml.MapLibreMapController? _controlador;
  var _estiloListo = false;
  String? _estilo;
  Object? _claveEstilo;
  var _avisoError = false;

  @override
  void didUpdateWidget(VistaMapLibre anterior) {
    super.didUpdateWidget(anterior);
    final config = widget.config;
    final antes = anterior.config;
    if (!listEquals(config.puntos, antes.puntos)) unawaited(_empujarPuntos());
    if (config.precision != antes.precision) unawaited(_empujarPrecision());
  }

  /// El estilo no cambia mientras no cambie lo que lo define: cambiarlo recarga la vista entera.
  /// Los puntos y el radio de precisión no lo definen (entran por `setGeoJsonSource`).
  String _estiloPara(RecursosMapa recursos) {
    final config = widget.config;
    final clave = (recursos, config.fuente, config.agruparPuntos, config.fondo, config.colorNuevo);
    if (_estilo == null || _claveEstilo != clave) {
      final directorio = recursos.directorio;
      _estilo = directorio == null
          ? ConstructorEstiloMapa.construirSinRecursos(
              estiloBase: recursos.estiloBase,
              config: config,
            )
          : ConstructorEstiloMapa.construir(
              estiloBase: recursos.estiloBase,
              directorioRecursos: directorio,
              config: config,
            );
      _claveEstilo = clave;
      _estiloListo = false;
    }
    return _estilo!;
  }

  Future<void> _empujarPuntos() async {
    final controlador = _controlador;
    if (controlador == null || !_estiloListo) return;
    try {
      await controlador.setGeoJsonSource(
        ConstructorEstiloMapa.fuentePuntos,
        ConstructorEstiloMapa.coleccionPuntos(widget.config.puntos),
      );
    } on Object catch (e, s) {
      AppLogger.instance.error(_modulo, 'puntos', 'No se pudieron actualizar los puntos', {}, e, s);
    }
  }

  Future<void> _empujarPrecision() async {
    final controlador = _controlador;
    if (controlador == null || !_estiloListo) return;
    try {
      await controlador.setGeoJsonSource(
        ConstructorEstiloMapa.fuentePrecision,
        ConstructorEstiloMapa.poligonoPrecision(widget.config.precision),
      );
    } on Object catch (e, s) {
      AppLogger.instance.error(_modulo, 'precision', 'No se pudo actualizar el radio', {}, e, s);
    }
  }

  void _alCargarEstilo() {
    _estiloListo = true;
    // Entre que se armó el estilo y se cargó pudieron cambiar los puntos.
    unawaited(_empujarPuntos());
    unawaited(_empujarPrecision());
  }

  CamaraMapa _aCamara(ml.CameraPosition posicion) => CamaraMapa(
    centro: Coordenadas(lat: posicion.target.latitude, lon: posicion.target.longitude),
    zoom: posicion.zoom,
  );

  void _alQuedarQuieta() {
    final posicion = _controlador?.cameraPosition;
    if (posicion != null) widget.eventos.camaraQuieta(_aCamara(posicion));
  }

  Future<void> _alTocar(math.Point<double> punto, ml.LatLng coordenadas) async {
    final controlador = _controlador;
    if (widget.config.puntosTocables && controlador != null) {
      try {
        final hallados = await controlador.queryRenderedFeatures(
          punto,
          ConstructorEstiloMapa.capasTocables,
          null,
        );
        if (hallados.isNotEmpty && await _tocarElemento(controlador, hallados.first)) return;
      } on Object catch (e, s) {
        AppLogger.instance.error(
          _modulo,
          'toque',
          'No se pudo consultar el punto tocado',
          {},
          e,
          s,
        );
      }
    }
    widget.eventos.toque(Coordenadas(lat: coordenadas.latitude, lon: coordenadas.longitude));
  }

  /// Un punto avisa su id; un grupo acerca el mapa hasta que se separe. `false` si no se entendió
  /// el elemento (el toque se trata como un toque al mapa).
  Future<bool> _tocarElemento(ml.MapLibreMapController controlador, Object? elemento) async {
    if (elemento is! Map<String, dynamic>) return false;
    final propiedades = elemento['properties'];
    if (propiedades is! Map<String, dynamic>) return false;
    if (propiedades['cluster'] == true) {
      final id = propiedades['cluster_id'];
      final geometria = elemento['geometry'];
      if (id is! num || geometria is! Map<String, dynamic>) return false;
      final coordenadas = geometria['coordinates'];
      if (coordenadas is! List<dynamic> || coordenadas.length < 2) return false;
      final zoom = await controlador.getClusterExpansionZoom(
        ConstructorEstiloMapa.fuentePuntos,
        id.toInt(),
      );
      await controlador.animateCamera(
        ml.CameraUpdate.newLatLngZoom(
          ml.LatLng((coordenadas[1] as num).toDouble(), (coordenadas[0] as num).toDouble()),
          zoom.toDouble(),
        ),
      );
      return true;
    }
    final id = propiedades['id'];
    if (id is! String) return false;
    widget.eventos.toquePunto(id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final recursos = ref.watch(recursosMapaProvider);
    return recursos.when(
      data: (r) => _mapa(config, _estiloPara(r)),
      loading: () => ColoredBox(color: config.fondo),
      error: (e, s) {
        if (!_avisoError) {
          _avisoError = true;
          AppLogger.instance.error(
            _modulo,
            'recursos',
            'No se pudieron preparar los recursos',
            {},
            e,
            s,
          );
        }
        return ColoredBox(color: config.fondo);
      },
    );
  }

  Widget _mapa(ConfigVistaMapa config, String estilo) {
    final camara = config.camaraInicial;
    return ml.MapLibreMap(
      styleString: estilo,
      initialCameraPosition: ml.CameraPosition(
        target: ml.LatLng(camara.centro.lat, camara.centro.lon),
        zoom: camara.zoom,
      ),
      minMaxZoomPreference: ml.MinMaxZoomPreference(config.zoomMinimo, config.zoomMaximo),
      scrollGesturesEnabled: config.interaccion.desplazar,
      zoomGesturesEnabled: config.interaccion.zoom,
      doubleClickZoomEnabled: config.dobleToqueZoom,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: false,
      logoEnabled: false,
      // La atribución («© OpenStreetMap») la dibuja `MapaBase`, en Flutter; el botón nativo se
      // corre fuera de la vista para que no se superponga con los controles de la pantalla.
      attributionButtonMargins: const math.Point(-200, -200),
      trackCameraPosition: true,
      // Los puntos son capas del estilo, no anotaciones: sin los administradores de anotaciones el
      // mapa dibuja más rápido.
      annotationOrder: const [],
      onMapCreated: (controlador) {
        _controlador = controlador;
        widget.eventos.listo(_PuertoMapLibre(controlador));
      },
      onStyleLoadedCallback: _alCargarEstilo,
      onCameraMove: (posicion) => widget.eventos.camaraMovida(_aCamara(posicion)),
      onCameraIdle: _alQuedarQuieta,
      onMapClick: (punto, coordenadas) => unawaited(_alTocar(punto, coordenadas)),
    );
  }
}

class _PuertoMapLibre implements PuertoVistaMapa {
  const _PuertoMapLibre(this._controlador);

  final ml.MapLibreMapController _controlador;

  @override
  Future<void> moverCamara(CamaraMapa camara) async {
    await _controlador.moveCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(camara.centro.lat, camara.centro.lon), camara.zoom),
    );
  }
}
