import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/fuente_mapa.dart';
import '../../domain/services/proyeccion_mercator.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../providers/mapa_base_providers.dart';
import 'modelo_mapa_base.dart';

/// El recuadro que tiene que quedar a la vista al abrir el mapa: la cámara más cercana que deja a
/// todos los [puntos] adentro, con [margen] píxeles libres en cada borde y sin pasar de
/// [zoomMaximo].
final class AjusteMapa extends Equatable {
  const AjusteMapa({required this.puntos, this.margen = 0, this.zoomMaximo = 18});

  final List<Coordenadas> puntos;
  final double margen;
  final double zoomMaximo;

  @override
  List<Object?> get props => [puntos, margen, zoomMaximo];
}

/// El mapa base de la app (vistas 03, 04, 06, 07 y 10): MapLibre Native con el estilo de backend
/// (#42), la paleta del canvas y los tiles de [fuente] —el paquete descargado, que anda sin red, o
/// el PMTiles online—. Sin tiles queda el color liso del diseño.
///
/// Los puntos, sus grupos y el radio de precisión del GPS se dibujan como capas del estilo, no
/// como widgets. La vista nativa está detrás de [ConstructorVistaMapa] (`constructorVistaMapaProvider`):
/// los tests de widgets la reemplazan por una falsa.
///
/// La cámara arranca en [camaraInicial] o en [ajuste] (uno de los dos). Después la mueve el
/// colportor (se avisa por [alMoverCamara]) o quien usa el mapa, por el [ControladorMapaBase] de
/// [alCrearse] (eso no se avisa como gesto).
class MapaBase extends ConsumerStatefulWidget {
  const MapaBase({
    super.key,
    required this.fuente,
    this.camaraInicial,
    this.ajuste,
    this.zoomMinimo = 3,
    this.zoomMaximo = 19,
    this.interaccion = const InteraccionMapa(),
    this.zoomSobreCentro = false,
    this.fondo = ColoresMapa.fondo,
    this.puntos = const [],
    this.agruparPuntos = false,
    this.precision,
    this.alCrearse,
    this.alMoverCamara,
    this.alQuedarQuieto,
    this.alTocar,
    this.alTocarPunto,
  }) : assert(camaraInicial != null || ajuste != null, 'Falta la cámara inicial o el ajuste');

  final FuenteMapa fuente;
  final CamaraMapa? camaraInicial;
  final AjusteMapa? ajuste;
  final double zoomMinimo;
  final double zoomMaximo;
  final InteraccionMapa interaccion;

  /// El zoom con el pellizco se hace sobre el centro del mapa: al soltar, el mapa vuelve al centro
  /// que tenía antes del pellizco. MapLibre acerca sobre el punto entre los dedos, y con un pin
  /// fijo en el centro eso correría el punto sin que el colportor lo mueva. Con esto activo se
  /// desactiva el zoom con doble toque, que también acerca sobre el punto tocado.
  final bool zoomSobreCentro;

  /// El color de fondo: lo que se ve sin tiles y mientras cargan.
  final Color fondo;
  final List<PuntoMapa> puntos;
  final bool agruparPuntos;
  final CirculoPrecision? precision;

  /// El mapa existe: [ControladorMapaBase] para moverlo y leer la cámara.
  final ValueChanged<ControladorMapaBase>? alCrearse;

  /// El colportor movió el mapa (arrastre, o zoom que no sea un pellizco con [zoomSobreCentro]).
  /// No avisa los movimientos que pidió el propio código ni lo que deja el pellizco.
  final ValueChanged<CamaraMapa>? alMoverCamara;

  /// El mapa dejó de moverse: la cámara y el área que se ve.
  final void Function(CamaraMapa camara, AreaMapa area)? alQuedarQuieto;

  /// Se tocó el mapa en [Coordenadas] (no un punto).
  final ValueChanged<Coordenadas>? alTocar;

  /// Se tocó el punto con ese [PuntoMapa.id]. Un grupo no avisa: acerca el mapa hasta separarse.
  final ValueChanged<String>? alTocarPunto;

  @override
  ConsumerState<MapaBase> createState() => _MapaBaseState();
}

class _MapaBaseState extends ConsumerState<MapaBase>
    implements ControladorMapaBase, EventosVistaMapa {
  /// Cuánto después de soltar el último dedo se restaura el centro si la vista no avisó antes que
  /// dejó de moverse.
  static const _esperaRestaurar = Duration(milliseconds: 350);

  /// Un movimiento de cámara a menos de esto del destino que pidió el código es el eco de ese
  /// pedido, no un gesto: 1e-6 grados son unos 11 cm.
  static const _toleranciaEcoGrados = 1e-6;

  CamaraMapa? _inicial;
  CamaraMapa? _camara;
  Size _tamano = Size.zero;

  PuertoVistaMapa? _puerto;
  CamaraMapa? _pendiente;
  CamaraMapa? _eco;

  final _dedos = <int>{};
  var _pellizcoPendiente = false;
  Coordenadas? _centroPrevioAlPellizco;
  Timer? _timerRestaurar;

  @override
  void initState() {
    super.initState();
    widget.alCrearse?.call(this);
  }

  @override
  void didUpdateWidget(MapaBase anterior) {
    super.didUpdateWidget(anterior);
    final ajuste = widget.ajuste;
    if (ajuste != null && ajuste != anterior.ajuste && _tamano.longestSide > 0) {
      unawaited(moverCamara(_resolverInicial()));
    }
  }

  @override
  void dispose() {
    _timerRestaurar?.cancel();
    super.dispose();
  }

  bool get _pellizcoSobreCentro => widget.zoomSobreCentro && widget.interaccion.zoom;

  CamaraMapa _resolverInicial() {
    final camara = widget.camaraInicial;
    if (camara != null) return camara;
    final ajuste = widget.ajuste!;
    return ProyeccionMercator.camaraQueAjusta(
      ajuste.puntos,
      ancho: _tamano.width,
      alto: _tamano.height,
      margen: ajuste.margen,
      zoomMaximo: ajuste.zoomMaximo,
    );
  }

  // ---- ControladorMapaBase --------------------------------------------------------------------

  @override
  CamaraMapa get camara => _camara ?? _inicial ?? _resolverInicial();

  @override
  Future<void> moverCamara(CamaraMapa camara) async {
    _camara = camara;
    _eco = camara;
    final puerto = _puerto;
    if (puerto == null) {
      _pendiente = camara;
      return;
    }
    await _mover(puerto, camara);
  }

  Future<void> _mover(PuertoVistaMapa puerto, CamaraMapa camara) async {
    try {
      await puerto.moverCamara(camara);
    } on Object catch (e, s) {
      AppLogger.instance.error(LogModulo.map, 'camara', 'No se pudo mover el mapa', {}, e, s);
    }
  }

  // ---- EventosVistaMapa -----------------------------------------------------------------------

  @override
  void listo(PuertoVistaMapa puerto) {
    if (!mounted) return;
    _puerto = puerto;
    final pendiente = _pendiente;
    _pendiente = null;
    if (pendiente != null) unawaited(_mover(puerto, pendiente));
    _informarQuieta(pendiente ?? camara);
  }

  @override
  void camaraMovida(CamaraMapa camara) {
    if (!mounted) return;
    _camara = camara;
    if (_esEcoDelCodigo(camara)) return;
    _eco = null;
    // Con el pellizco el centro se corre (el zoom es sobre los dedos): se restaura al soltar.
    if (_pellizcoPendiente) return;
    widget.alMoverCamara?.call(camara);
  }

  @override
  void camaraQuieta(CamaraMapa camara) {
    if (!mounted) return;
    _camara = camara;
    // Lo que sigue ya no es el eco de un pedido del código.
    _eco = null;
    if (_pellizcoPendiente) {
      if (_dedos.isEmpty) _restaurarCentroTrasPellizco();
      return;
    }
    _informarQuieta(camara);
  }

  @override
  void toque(Coordenadas coordenadas) {
    if (mounted) widget.alTocar?.call(coordenadas);
  }

  @override
  void toquePunto(String id) {
    if (mounted) widget.alTocarPunto?.call(id);
  }

  bool _esEcoDelCodigo(CamaraMapa camara) {
    final esperada = _eco;
    if (esperada == null) return false;
    return (camara.centro.lat - esperada.centro.lat).abs() < _toleranciaEcoGrados &&
        (camara.centro.lon - esperada.centro.lon).abs() < _toleranciaEcoGrados;
  }

  void _informarQuieta(CamaraMapa camara) {
    final alQuedarQuieto = widget.alQuedarQuieto;
    if (alQuedarQuieto == null) return;
    final area = ProyeccionMercator.areaVisible(camara, ancho: _tamano.width, alto: _tamano.height);
    alQuedarQuieto(camara, area);
  }

  // ---- Pellizco sobre el centro ---------------------------------------------------------------

  void _alBajarDedo(PointerDownEvent evento) {
    _dedos.add(evento.pointer);
    _timerRestaurar?.cancel();
    if (_dedos.length >= 2 && _pellizcoSobreCentro && !_pellizcoPendiente) {
      _pellizcoPendiente = true;
      _centroPrevioAlPellizco = camara.centro;
    }
  }

  void _alSoltarDedo(PointerEvent evento) {
    _dedos.remove(evento.pointer);
    if (_dedos.isEmpty && _pellizcoPendiente) {
      // Lo normal es que la vista avise que dejó de moverse y ahí se restaura; esto es por si no.
      _timerRestaurar?.cancel();
      _timerRestaurar = Timer(_esperaRestaurar, _restaurarCentroTrasPellizco);
    }
  }

  void _restaurarCentroTrasPellizco() {
    _timerRestaurar?.cancel();
    if (!_pellizcoPendiente || !mounted) return;
    _pellizcoPendiente = false;
    final centro = _centroPrevioAlPellizco;
    _centroPrevioAlPellizco = null;
    if (centro == null) return;
    final destino = CamaraMapa(centro: centro, zoom: camara.zoom);
    unawaited(moverCamara(destino));
    _informarQuieta(destino);
  }

  // ---- Dibujo ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final constructor = ref.watch(constructorVistaMapaProvider);
    final colorNuevo = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, restricciones) {
        final tamano = restricciones.biggest;
        _tamano = Size(
          tamano.width.isFinite ? tamano.width : 0,
          tamano.height.isFinite ? tamano.height : 0,
        );
        final inicial = _inicial ??= _resolverInicial();
        _camara ??= inicial;
        final config = ConfigVistaMapa(
          fuente: widget.fuente,
          camaraInicial: inicial,
          zoomMinimo: widget.zoomMinimo,
          zoomMaximo: widget.zoomMaximo,
          interaccion: widget.interaccion,
          dobleToqueZoom: widget.interaccion.zoom && !widget.zoomSobreCentro,
          fondo: widget.fondo,
          colorNuevo: colorNuevo,
          puntos: widget.puntos,
          agruparPuntos: widget.agruparPuntos,
          precision: widget.precision,
          puntosTocables: widget.alTocarPunto != null,
        );
        Widget vista = constructor(context, config, this);
        // Sin gestos el mapa es una imagen: los toques siguen de largo hacia el scroll de la
        // pantalla donde esté (la vista nativa los reclamaría todos).
        if (!widget.interaccion.hay) vista = IgnorePointer(child: vista);
        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _alBajarDedo,
              onPointerUp: _alSoltarDedo,
              onPointerCancel: _alSoltarDedo,
              child: vista,
            ),
            if (widget.fuente.hayTiles) const _AtribucionOsm(),
          ],
        );
      },
    );
  }
}

/// «© OpenStreetMap»: la atribución que pide la licencia de los datos (ODbL).
class _AtribucionOsm extends StatelessWidget {
  const _AtribucionOsm();

  static const texto = '© OpenStreetMap';

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 6,
      bottom: 6,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xCCFFFFFF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(
                texto,
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 10, height: 1.2, color: ColoresMapa.tinta),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
