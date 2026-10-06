import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/gestures.dart';
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

  /// El zoom con los dedos se hace sobre el centro del mapa: el pellizco y el doble toque (con su
  /// variante de un dedo, tocar y arrastrar) acercan y, al terminar, el mapa vuelve al centro que
  /// tenía antes, con el zoom nuevo. MapLibre acerca sobre el punto entre los dedos (o el tocado), y
  /// con un pin fijo en el centro eso correría el punto sin que el colportor lo mueva. El doble
  /// toque no se apaga: es la forma de acercar con un solo dedo.
  final bool zoomSobreCentro;

  /// La etiqueta del nodo de accesibilidad del punto del GPS (el canvas lo marca como imagen
  /// «Tu ubicación»). La precisión no se repite ahí: la dice el chip «GPS ±N m».
  static const textoTuUbicacion = 'Tu ubicación';

  /// El color de fondo: lo que se ve sin tiles y mientras cargan.
  final Color fondo;

  /// Lo que se dibuja encima del mapa. El punto [EstiloPunto.gps] además le suma al lector de
  /// pantalla un nodo «Tu ubicación» sobre el punto, sin acción, ubicado con la cámara de la última
  /// vez que el mapa quedó quieto; si el punto queda fuera de la pantalla no hay nodo.
  final List<PuntoMapa> puntos;
  final bool agruparPuntos;
  final CirculoPrecision? precision;

  /// El mapa existe: [ControladorMapaBase] para moverlo y leer la cámara.
  final ValueChanged<ControladorMapaBase>? alCrearse;

  /// El colportor movió el mapa (arrastre, o zoom que no sea de los de [zoomSobreCentro]). No avisa
  /// los movimientos que pidió el propio código ni lo que deja el zoom sobre el centro.
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
  /// Cuánto después de soltar el último dedo de un pellizco se restaura el centro si la vista no
  /// avisó antes que dejó de moverse.
  static const _esperaRestaurarPellizco = Duration(milliseconds: 350);

  /// Cuánto después de un toque corto puede caer el segundo para que sea un doble toque (el mismo
  /// plazo de Android y de Flutter).
  static const _ventanaDobleToque = kDoubleTapTimeout;

  /// Lo mismo con el doble toque: MapLibre acerca con una animación (~300 ms) que arranca al soltar
  /// el segundo toque, y se la espera entera antes de dar por hecho que no hubo zoom.
  static const _esperaRestaurarDobleToque = Duration(milliseconds: 1000);

  /// El lado del nodo de «Tu ubicación»: lo que mide el punto azul (radio 9,5 más el borde).
  static const _ladoMarcaGps = 24.0;

  /// Un movimiento de cámara a menos de esto del destino que pidió el código es el eco de ese
  /// pedido, no un gesto: 1e-6 grados son unos 11 cm.
  static const _toleranciaEcoGrados = 1e-6;

  CamaraMapa? _inicial;
  CamaraMapa? _camara;
  Size _tamano = Size.zero;

  PuertoVistaMapa? _puerto;
  CamaraMapa? _pendiente;
  CamaraMapa? _eco;

  /// La cámara de la última vez que el mapa quedó quieto: con ella se ubica el nodo de «Tu ubicación».
  CamaraMapa? _camaraQuieta;

  final _dedos = <int, _Dedo>{};

  /// En lo que va del gesto hubo dos dedos a la vez (no es un toque).
  var _hubo2Dedos = false;

  /// Hay un zoom sobre el centro en curso (pellizco o doble toque): el centro se corre mientras
  /// dura y se restaura al terminar. No es un gesto del colportor.
  var _zoomPendiente = false;
  var _esDobleToque = false;
  int? _dedoDelDobleToque;

  /// Desde que arrancó el zoom llegó al menos un movimiento de cámara.
  var _huboMovimiento = false;
  Coordenadas? _centroPrevio;
  Timer? _timerRestaurar;

  /// Dónde cayó el último toque corto, mientras todavía puede ser el primero de un doble toque.
  Offset? _ultimoToque;
  Timer? _timerUltimoToque;

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
    _timerUltimoToque?.cancel();
    super.dispose();
  }

  bool get _zoomSobreCentro => widget.zoomSobreCentro && widget.interaccion.zoom;

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
    // Con un zoom sobre el centro en curso, lo que pide el código (por ejemplo, centrar en el punto
    // que se tocó) es el centro al que se vuelve al terminar, no el de antes del zoom.
    if (_zoomPendiente) _centroPrevio = camara.centro;
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
    // Con el zoom sobre el centro este se corre (el zoom es sobre los dedos o el punto tocado): se
    // restaura al terminar.
    if (_zoomPendiente) {
      _huboMovimiento = true;
      return;
    }
    widget.alMoverCamara?.call(camara);
  }

  @override
  void camaraQuieta(CamaraMapa camara) {
    if (!mounted) return;
    _camara = camara;
    // Lo que sigue ya no es el eco de un pedido del código.
    _eco = null;
    if (_zoomPendiente) {
      // El doble toque anima: un «quieta» de antes de que arrancara no es el final del zoom.
      if (_dedos.isEmpty && (!_esDobleToque || _huboMovimiento)) _restaurarCentro();
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
    _camaraQuieta = camara;
    // El nodo «Tu ubicación» se reubica cuando el mapa queda quieto.
    if (mounted && _puntoGps != null) setState(() {});
    final alQuedarQuieto = widget.alQuedarQuieto;
    if (alQuedarQuieto == null) return;
    final area = ProyeccionMercator.areaVisible(camara, ancho: _tamano.width, alto: _tamano.height);
    alQuedarQuieto(camara, area);
  }

  // ---- Zoom sobre el centro -------------------------------------------------------------------
  //
  // MapLibre acerca sobre los dedos (pellizco) o sobre el punto tocado (doble toque, y tocar dos
  // veces y arrastrar): el centro se corre. Con [MapaBase.zoomSobreCentro] ese corrimiento no cuenta
  // como un gesto del colportor y, al terminar, el mapa vuelve al centro que tenía. El doble toque
  // se reconoce acá, con los punteros que ve el `Listener`, porque la vista nativa no avisa qué
  // gesto fue: solo manda cámaras.

  void _alBajarDedo(PointerDownEvent evento) {
    _timerRestaurar?.cancel();
    final segundoToque = _dedos.isEmpty && _esSegundoToque(evento.position);
    _olvidarUltimoToque();
    _dedos[evento.pointer] = _Dedo(evento.position);
    if (_dedos.length >= 2) _hubo2Dedos = true;
    if (!_zoomSobreCentro || _zoomPendiente) return;
    if (_dedos.length >= 2) {
      _iniciarZoom(dobleToque: false);
    } else if (segundoToque) {
      _iniciarZoom(dobleToque: true);
      _dedoDelDobleToque = evento.pointer;
    }
  }

  void _alMoverDedo(PointerMoveEvent evento) {
    final dedo = _dedos[evento.pointer];
    if (dedo == null) return;
    dedo.posicion = evento.position;
    // Un pellizco que ya terminó y un dedo que sigue arrastrando (o tocar, soltar un dedo y
    // arrastrar con el otro): es un arrastre del colportor, no el resto del zoom. Se avisa y se
    // deja de restaurar el centro, así no se descarta el ajuste. El dedo del doble toque en sí
    // (tocar dos veces y arrastrar) sí es zoom.
    if (_zoomPendiente &&
        _dedos.length == 1 &&
        evento.pointer != _dedoDelDobleToque &&
        dedo.seMovioDesdeReferencia) {
      _terminarZoomPorArrastre();
    }
  }

  void _alSoltarDedo(PointerEvent evento) {
    final dedo = _dedos.remove(evento.pointer);
    if (dedo == null) return;
    if (_dedos.length == 1) {
      // El que queda ya no hace pellizco: lo que se mueva desde acá cuenta como arrastre.
      _dedos.values.single.reiniciarReferencia();
    }
    if (_dedos.isNotEmpty) return;
    final fueToque = evento is PointerUpEvent && !_hubo2Dedos && !dedo.seMovioDesdeElInicio;
    _hubo2Dedos = false;
    if (_zoomPendiente) {
      // Lo normal es que la vista avise que dejó de moverse y ahí se restaura; esto es por si no.
      _timerRestaurar?.cancel();
      _timerRestaurar = Timer(
        _esDobleToque ? _esperaRestaurarDobleToque : _esperaRestaurarPellizco,
        _restaurarCentro,
      );
    } else if (fueToque && _zoomSobreCentro) {
      _ultimoToque = evento.position;
      _timerUltimoToque = Timer(_ventanaDobleToque, _olvidarUltimoToque);
    }
  }

  bool _esSegundoToque(Offset posicion) {
    final anterior = _ultimoToque;
    return anterior != null && (posicion - anterior).distance <= kDoubleTapSlop;
  }

  void _olvidarUltimoToque() {
    _timerUltimoToque?.cancel();
    _timerUltimoToque = null;
    _ultimoToque = null;
  }

  void _iniciarZoom({required bool dobleToque}) {
    _zoomPendiente = true;
    _esDobleToque = dobleToque;
    _huboMovimiento = false;
    _centroPrevio = camara.centro;
  }

  /// Termina el zoom pendiente sin volver al centro: lo que sigue es un arrastre, y se avisa como
  /// tal (con la cámara de ahora; los siguientes movimientos llegan solos).
  void _terminarZoomPorArrastre() {
    _timerRestaurar?.cancel();
    _limpiarZoom();
    widget.alMoverCamara?.call(camara);
  }

  void _limpiarZoom() {
    _zoomPendiente = false;
    _esDobleToque = false;
    _huboMovimiento = false;
    _dedoDelDobleToque = null;
    _centroPrevio = null;
  }

  void _restaurarCentro() {
    _timerRestaurar?.cancel();
    if (!_zoomPendiente || !mounted) return;
    final centro = _centroPrevio;
    _limpiarZoom();
    if (centro == null) return;
    final destino = CamaraMapa(centro: centro, zoom: camara.zoom);
    unawaited(moverCamara(destino));
    _informarQuieta(destino);
  }

  // ---- «Tu ubicación» -------------------------------------------------------------------------

  /// El punto del GPS, si el mapa lo dibuja.
  PuntoMapa? get _puntoGps {
    for (final punto in widget.puntos) {
      if (punto.estilo == EstiloPunto.gps) return punto;
    }
    return null;
  }

  /// Dónde cae el punto del GPS en la vista, con la cámara de la última vez que el mapa quedó
  /// quieto; `null` si no hay punto, la vista no está lista o el punto queda fuera de la pantalla.
  Offset? _posicionDelGps() {
    final punto = _puntoGps;
    final camara = _camaraQuieta;
    if (punto == null || camara == null || _tamano.isEmpty) return null;
    final enMundo = ProyeccionMercator.aPixeles(punto.coordenadas, camara.zoom);
    final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
    final x = enMundo.x - centro.x + _tamano.width / 2;
    final y = enMundo.y - centro.y + _tamano.height / 2;
    if (x < 0 || x > _tamano.width || y < 0 || y > _tamano.height) return null;
    return Offset(x, y);
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
          dobleToqueZoom: widget.interaccion.zoom,
          fondo: widget.fondo,
          colorNuevo: colorNuevo,
          puntos: widget.puntos,
          agruparPuntos: widget.agruparPuntos,
          precision: widget.precision,
          puntosTocables: widget.alTocarPunto != null,
        );
        final marcaGps = _posicionDelGps();
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
              onPointerMove: _alMoverDedo,
              onPointerUp: _alSoltarDedo,
              onPointerCancel: _alSoltarDedo,
              child: vista,
            ),
            if (marcaGps != null)
              Positioned(
                left: marcaGps.dx - _ladoMarcaGps / 2,
                top: marcaGps.dy - _ladoMarcaGps / 2,
                width: _ladoMarcaGps,
                height: _ladoMarcaGps,
                // Sin acción ni dibujo: solo el nodo que le dice a TalkBack dónde está el punto
                // azul (que es una capa del estilo y no un widget). No atrapa toques.
                child: Semantics(
                  container: true,
                  image: true,
                  label: MapaBase.textoTuUbicacion,
                  child: const SizedBox.expand(),
                ),
              ),
            if (widget.fuente.hayTiles) const _AtribucionOsm(),
          ],
        );
      },
    );
  }
}

/// Un dedo apoyado en el mapa: dónde empezó y dónde está.
class _Dedo {
  _Dedo(this.posicion) : inicio = posicion, referencia = posicion;

  final Offset inicio;
  Offset posicion;

  /// Desde dónde se mide si el dedo se movió «de verdad» ([kTouchSlop]): al apoyarse, o al soltarse
  /// el otro dedo de un pellizco.
  Offset referencia;

  bool get seMovioDesdeElInicio => (posicion - inicio).distance > kTouchSlop;
  bool get seMovioDesdeReferencia => (posicion - referencia).distance > kTouchSlop;

  void reiniciarReferencia() => referencia = posicion;
}

/// «© OpenStreetMap»: la atribución que pide la licencia de los datos (ODbL). Crece con el texto del
/// sistema y el lector de pantalla la lee. Si no entra en una línea baja a dos renglones, sin
/// elipsis, y a la derecha deja libre lo que ocupa un botón flotante del mapa.
class _AtribucionOsm extends StatelessWidget {
  const _AtribucionOsm();

  static const texto = '© OpenStreetMap';

  /// Del borde derecho: un botón de 52 dp a 14 dp del borde, y un respiro.
  static const _reservaDerecha = 80.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 6,
      right: _reservaDerecha,
      bottom: 4,
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: IgnorePointer(
          // Un nodo propio para el lector de pantalla: no se mezcla con el rótulo del mapa.
          child: Semantics(
            container: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCCFFFFFF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  texto,
                  style: TextStyle(fontSize: 10, height: 1.2, color: ColoresMapa.tinta),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
