import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/marcador_mapa.dart';
import '../../domain/services/proyeccion_mercator.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';
import '../mapa_base/mapa_base.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/alta_ubicacion_providers.dart';
import '../providers/mapa_base_providers.dart';
import 'piezas_alta.dart';

/// El mapa de la vista 03: el pin queda fijo en el centro y se mueve el mapa; un toque en el mapa
/// lo centra ahí. Dibuja la lectura del GPS (punto azul y radio de precisión) y las ubicaciones
/// que el colportor ya tiene alrededor, sin estado de visita (todavía no está en el teléfono).
///
/// Es un [MapaBase] (MapLibre): los tiles salen de `fuenteMapaProvider` y, sin ellos (HU-UBI-003),
/// queda el color liso del diseño.
class MapaAlta extends ConsumerStatefulWidget {
  const MapaAlta({
    super.key,
    required this.parametros,
    required this.estado,
    required this.alMoverCentro,
    required this.alTocar,
  });

  final ParametrosAlta parametros;
  final AltaUbicacionState estado;

  /// El colportor movió el mapa con el dedo: el nuevo centro.
  final ValueChanged<Coordenadas> alMoverCentro;

  /// El colportor tocó el mapa en [Coordenadas].
  final ValueChanged<Coordenadas> alTocar;

  /// Dónde se centra el mapa si no hay GPS ni punto: Uruguay entero (HU-UBI-003, «ciudad del
  /// colportor» todavía no se conoce).
  static const centroPorDefecto = Coordenadas(lat: -32.5228, lon: -55.7658);

  // Los zoom del alta. Se eligieron con `flutter_map` (#267, teselas de 256 px) y MapLibre usa
  // teselas de 512 px: el mismo número se ve al doble de cerca (Uruguay no entraría en la pantalla
  // y el radio de ±85 m la llenaría de borde a borde). `zoomDeFlutterMap` es la traducción: los
  // números de acá son los de #267, no se escriben ya convertidos.

  /// Uruguay entero a la vista (en `flutter_map`, 6,5).
  static final zoomPais = ProyeccionMercator.zoomDeFlutterMap(6.5);

  /// El nivel de una calle, donde se ve el radio de precisión del GPS (en `flutter_map`, 17).
  static final zoomCalle = ProyeccionMercator.zoomDeFlutterMap(17);

  /// Hasta dónde se aleja y se acerca el colportor con los dedos (en `flutter_map`, 3 y 19).
  static final zoomMinimo = ProyeccionMercator.zoomDeFlutterMap(3);
  static final zoomMaximo = ProyeccionMercator.zoomDeFlutterMap(19);

  /// Lo más cerca que se encuadra la vista previa de la hoja de duplicados (04), cuando la nueva y
  /// la candidata están a pocos metros (en `flutter_map`, 18).
  static final zoomMaximoVistaPrevia = ProyeccionMercator.zoomDeFlutterMap(18);

  /// Cuánto tiene que correrse el centro del mapa, en píxeles, para que cuente como «movió el
  /// punto». Un zoom o un temblor del dedo no mueven el pin: el punto del GPS sigue siendo del GPS.
  static const umbralMovimientoPx = 6.0;

  @override
  ConsumerState<MapaAlta> createState() => _MapaAltaState();
}

class _MapaAltaState extends ConsumerState<MapaAlta> {
  ControladorMapaBase? _mapa;
  AreaMapa? _area;

  /// El centro del mapa donde está el punto: el del último centrado, o el último que se le avisó al
  /// estado. Mientras el punto sea el del GPS (o no haya), un gesto que no se aleja de acá más del
  /// umbral —un zoom con el pellizco, por ejemplo— no lo mueve.
  Coordenadas? _centroDelPunto;

  @override
  void didUpdateWidget(MapaAlta anterior) {
    super.didUpdateWidget(anterior);
    if (widget.estado.movimientosCamara != anterior.estado.movimientosCamara) _centrar();
  }

  void _alCrearse(ControladorMapaBase mapa) {
    _mapa = mapa;
    _centroDelPunto ??= mapa.camara.centro;
  }

  void _centrar() {
    final punto = widget.estado.punto;
    final mapa = _mapa;
    if (punto == null || mapa == null) return;
    final zoom = mapa.camara.zoom;
    _centroDelPunto = punto;
    unawaited(
      mapa.moverCamara(CamaraMapa(centro: punto, zoom: math.max(zoom, MapaAlta.zoomCalle))),
    );
  }

  /// ¿Los gestos movieron el centro lo suficiente como para mover el punto?
  ///
  /// Una vez que el punto es «a mano» se informa todo movimiento, para que quede exacto donde el
  /// colportor soltó el mapa. El umbral solo protege al punto del GPS (o al pin sin colocar) de los
  /// gestos que no lo mueven.
  bool _movioElPunto(CamaraMapa camara) {
    if (widget.estado.origen == OrigenCoordenadas.manual && widget.estado.punto != null) {
      return true;
    }
    final referencia = _centroDelPunto;
    if (referencia == null) return true;
    final distancia = ProyeccionMercator.distanciaPixeles(camara.centro, referencia, camara.zoom);
    return distancia > MapaAlta.umbralMovimientoPx;
  }

  void _alMoverCamara(CamaraMapa camara) {
    if (!_movioElPunto(camara)) return;
    _centroDelPunto = camara.centro;
    widget.alMoverCentro(camara.centro);
  }

  void _alQuedarQuieto(CamaraMapa camara, AreaMapa area) {
    if (!mounted) return;
    if (area.esValida && area != _area) setState(() => _area = area);
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final punto = estado.punto ?? estado.lectura?.coordenadas;
    final centro = punto ?? MapaAlta.centroPorDefecto;
    final area = _area;
    final cercanos = area == null
        ? const <MarcadorMapa>[]
        : ref
                  .watch(
                    marcadoresCercanosProvider((
                      colportorId: widget.parametros.colportorId,
                      area: area,
                    )),
                  )
                  .value ??
              const <MarcadorMapa>[];
    // El punto azul y el radio de precisión solo con una lectura vigente del GPS.
    final lectura = estado.gps == EstadoGps.conLectura ? estado.lectura : null;

    return Semantics(
      label: 'Mapa. Mové el mapa para ajustar el punto de la nueva ubicación.',
      container: true,
      child: MapaBase(
        fuente: ref.watch(fuenteMapaProvider),
        camaraInicial: CamaraMapa(
          centro: centro,
          zoom: punto == null ? MapaAlta.zoomPais : MapaAlta.zoomCalle,
        ),
        zoomMinimo: MapaAlta.zoomMinimo,
        zoomMaximo: MapaAlta.zoomMaximo,
        fondo: ColoresAlta.fondoMapa,
        // Sin rotar y con el zoom sobre el centro: el pin está fijo en el centro, así el punto no se
        // corre al acercar o alejar el mapa.
        zoomSobreCentro: true,
        puntos: [
          for (final m in cercanos) PuntoMapa(id: m.ubicacionId, coordenadas: m.coordenadas),
          if (lectura != null)
            PuntoMapa(id: 'gps', coordenadas: lectura.coordenadas, estilo: EstiloPunto.gps),
        ],
        precision: lectura != null
            ? CirculoPrecision(
                centro: lectura.coordenadas,
                radioMetros: lectura.precisionMetros.isFinite ? lectura.precisionMetros : 0,
              )
            : null,
        alCrearse: _alCrearse,
        alMoverCamara: _alMoverCamara,
        alQuedarQuieto: _alQuedarQuieto,
        alTocar: widget.alTocar,
      ),
    );
  }
}
