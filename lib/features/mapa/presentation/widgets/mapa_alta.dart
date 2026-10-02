import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/marcador_mapa.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../providers/alta_ubicacion_providers.dart';
import 'piezas_alta.dart';

/// El mapa de la vista 03: el pin queda fijo en el centro y se mueve el mapa; un toque en el mapa
/// lo centra ahí. Dibuja la lectura del GPS (punto azul y radio de precisión) y las ubicaciones
/// que el colportor ya tiene alrededor, sin estado de visita (todavía no está en el teléfono).
///
/// Sin paquete de tiles ni servidor (HU-UBI-003, #199) no hay fondo: queda el color liso del
/// diseño.
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
  static const centroPorDefecto = LatLng(-32.5228, -55.7658);
  static const zoomPais = 6.5;
  static const zoomCalle = 17.0;

  /// Cuánto tiene que correrse el centro del mapa, en píxeles, para que cuente como «movió el
  /// punto». Un zoom o un temblor del dedo no mueven el pin: el punto del GPS sigue siendo del GPS.
  static const umbralMovimientoPx = 6.0;

  @override
  ConsumerState<MapaAlta> createState() => _MapaAltaState();
}

class _MapaAltaState extends ConsumerState<MapaAlta> {
  final _controlador = MapController();
  var _listo = false;
  AreaMapa? _area;
  Timer? _esperaArea;

  /// El centro del mapa donde está el punto: el del último centrado, o el último que se le avisó al
  /// estado. Mientras el punto sea el del GPS (o no haya), un gesto que no se aleja de acá más del
  /// umbral —un zoom con el pellizco, por ejemplo— no lo mueve.
  LatLng? _centroDelPunto;

  @override
  void didUpdateWidget(MapaAlta anterior) {
    super.didUpdateWidget(anterior);
    if (widget.estado.movimientosCamara != anterior.estado.movimientosCamara) _centrar();
  }

  @override
  void dispose() {
    _esperaArea?.cancel();
    _controlador.dispose();
    super.dispose();
  }

  void _centrar() {
    final punto = widget.estado.punto;
    if (punto == null || !_listo) return;
    final zoom = _controlador.camera.zoom;
    final centro = LatLng(punto.lat, punto.lon);
    _centroDelPunto = centro;
    _controlador.move(centro, zoom < MapaAlta.zoomCalle ? MapaAlta.zoomCalle : zoom);
  }

  /// ¿Los gestos movieron el centro lo suficiente como para mover el punto?
  ///
  /// Una vez que el punto es «a mano» se informa todo movimiento, para que quede exacto donde el
  /// colportor soltó el mapa. El umbral solo protege al punto del GPS (o al pin sin colocar) de los
  /// gestos que no lo mueven.
  bool _movioElPunto(MapCamera camara) {
    if (widget.estado.origen == OrigenCoordenadas.manual && widget.estado.punto != null) {
      return true;
    }
    final referencia = _centroDelPunto;
    if (referencia == null) return true;
    final distancia =
        (camara.projectAtZoom(camara.center) - camara.projectAtZoom(referencia)).distance;
    return distancia > MapaAlta.umbralMovimientoPx;
  }

  void _alCambiarCamara(MapCamera camara, bool conGesto) {
    if (conGesto && _movioElPunto(camara)) {
      _centroDelPunto = camara.center;
      widget.alMoverCentro(Coordenadas(lat: camara.center.latitude, lon: camara.center.longitude));
    }
    _esperaArea?.cancel();
    _esperaArea = Timer(const Duration(milliseconds: 400), () => _actualizarArea(camara));
  }

  void _actualizarArea(MapCamera camara) {
    if (!mounted) return;
    final b = camara.visibleBounds;
    final area = AreaMapa(sur: b.south, oeste: b.west, norte: b.north, este: b.east);
    if (area.esValida && area != _area) setState(() => _area = area);
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final punto = estado.punto ?? estado.lectura?.coordenadas;
    final centro = punto == null ? MapaAlta.centroPorDefecto : LatLng(punto.lat, punto.lon);
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
    final lectura = estado.lectura;

    return Semantics(
      label: 'Mapa. Mové el mapa para ajustar el punto de la nueva ubicación.',
      container: true,
      child: FlutterMap(
        mapController: _controlador,
        options: MapOptions(
          initialCenter: centro,
          initialZoom: punto == null ? MapaAlta.zoomPais : MapaAlta.zoomCalle,
          minZoom: 3,
          maxZoom: 19,
          backgroundColor: ColoresAlta.fondoMapa,
          // Sin rotar y sin que el pellizco arrastre: el pin está fijo en el centro y el zoom se hace
          // sobre él, así el punto no se corre al acercar o alejar el mapa.
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.pinchMove,
          ),
          onMapReady: () {
            _listo = true;
            _centroDelPunto ??= _controlador.camera.center;
            _actualizarArea(_controlador.camera);
          },
          onPositionChanged: _alCambiarCamara,
          onTap: (_, p) => widget.alTocar(Coordenadas(lat: p.latitude, lon: p.longitude)),
        ),
        children: [
          if (lectura != null && estado.gps == EstadoGps.conLectura)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(lectura.coordenadas.lat, lectura.coordenadas.lon),
                  radius: lectura.precisionMetros.isFinite ? lectura.precisionMetros : 0,
                  useRadiusInMeter: true,
                  color: ColoresAlta.puntoGps.withValues(alpha: .14),
                  borderColor: ColoresAlta.puntoGps.withValues(alpha: .45),
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              for (final m in cercanos)
                Marker(
                  point: LatLng(m.lat, m.lon),
                  width: 24,
                  height: 24,
                  child: const ExcludeSemantics(child: _MarcadorContexto()),
                ),
              if (lectura != null && estado.gps == EstadoGps.conLectura)
                Marker(
                  point: LatLng(lectura.coordenadas.lat, lectura.coordenadas.lon),
                  width: 18,
                  height: 18,
                  child: const _PuntoGps(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una ubicación que ya existe, sin estado de visita: círculo blanco con borde gris (el «Sin
/// visita» del diseño).
class _MarcadorContexto extends StatelessWidget {
  const _MarcadorContexto();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF6B7688), width: 2.5),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
    );
  }
}

/// «Tu ubicación»: el punto azul del GPS.
class _PuntoGps extends StatelessWidget {
  const _PuntoGps();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tu ubicación',
      child: Container(
        decoration: BoxDecoration(
          color: ColoresAlta.puntoGps,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: ColoresAlta.puntoGps.withValues(alpha: .16), spreadRadius: 8),
          ],
        ),
      ),
    );
  }
}
