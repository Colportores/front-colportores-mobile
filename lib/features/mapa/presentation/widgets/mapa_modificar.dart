import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/marcador_mapa.dart';
import '../../domain/services/proyeccion_mercator.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../mapa_base/mapa_base.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../providers/alta_ubicacion_providers.dart';
import '../providers/mapa_base_providers.dart';
import '../providers/modificar_ubicacion_notifier.dart';
import 'mapa_alta.dart';
import 'piezas_alta.dart';

/// El mapa de la vista 07 (HU-UBI-004): el pin de la ubicación fijo en el centro y, si el punto se
/// movió, el «fantasma» de dónde estaba («Antes») unido al pin por una línea punteada.
///
/// - En «Editar ubicación» el mapa es una imagen: no responde a ningún gesto, para que la posición no
///   cambie sin querer (canvas 07). Se mueve recién con «Mover el punto».
/// - En «Mover el punto» se arrastra el mapa y el pin, fijo en el centro, queda donde se suelta; un
///   toque en el mapa lo centra ahí.
///
/// Es un [MapaBase] (MapLibre): los tiles salen de `fuenteMapaProvider` y, sin ellos, queda el color
/// liso del diseño.
class MapaModificar extends ConsumerStatefulWidget {
  const MapaModificar({
    super.key,
    required this.colportorId,
    required this.estado,
    required this.alMoverCentro,
    required this.alTocar,
  });

  final String colportorId;
  final ModificarUbicacionState estado;

  /// El colportor movió el mapa con el dedo (solo en «Mover el punto»): el nuevo centro.
  final ValueChanged<Coordenadas> alMoverCentro;

  /// El colportor tocó el mapa en [Coordenadas] (solo en «Mover el punto»).
  final ValueChanged<Coordenadas> alTocar;

  /// Lo que se mueve el punto para que cuente como movido y se dibuje «Antes»: menos de un metro es
  /// el mismo punto.
  static const metrosParaFantasma = 1.0;

  @override
  ConsumerState<MapaModificar> createState() => _MapaModificarState();
}

class _MapaModificarState extends ConsumerState<MapaModificar> {
  ControladorMapaBase? _mapa;
  AreaMapa? _area;

  /// Hacia dónde mira el mapa ahora: con eso se ubica el fantasma sobre el mapa sin reconstruirlo.
  final _camara = ValueNotifier<CamaraMapa?>(null);

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MapaModificar anterior) {
    super.didUpdateWidget(anterior);
    if (widget.estado.movimientosCamara != anterior.estado.movimientosCamara) _centrar();
  }

  void _alCrearse(ControladorMapaBase mapa) {
    _mapa = mapa;
    _camara.value = mapa.camara;
  }

  void _centrar() {
    final punto = widget.estado.puntoVisible;
    final mapa = _mapa;
    if (punto == null || mapa == null) return;
    final nueva = CamaraMapa(centro: punto, zoom: math.max(mapa.camara.zoom, MapaAlta.zoomCalle));
    _camara.value = nueva;
    unawaited(mapa.moverCamara(nueva));
  }

  void _alMoverCamara(CamaraMapa camara) {
    _camara.value = camara;
    if (widget.estado.modo == ModoEdicion.moverPunto) widget.alMoverCentro(camara.centro);
  }

  void _alQuedarQuieto(CamaraMapa camara, AreaMapa area) {
    if (!mounted) return;
    _camara.value = camara;
    if (area.esValida && area != _area) setState(() => _area = area);
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final original = estado.original!;
    final mover = estado.modo == ModoEdicion.moverPunto;
    final punto = estado.puntoVisible ?? original.coordenadas;
    final area = _area;
    final cercanos = area == null
        ? const <MarcadorMapa>[]
        : ref
                  .watch(marcadoresCercanosProvider((colportorId: widget.colportorId, area: area)))
                  .value ??
              const <MarcadorMapa>[];
    final lectura = mover ? estado.lectura : null;
    final movidos = estado.metrosMovidos ?? 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: mover
              ? 'Mapa. Mové el mapa para ajustar el punto de la ubicación.'
              : 'Mapa de la ubicación. Tocá «Mover el punto» para cambiar su posición.',
          container: true,
          child: MapaBase(
            fuente: ref.watch(fuenteMapaProvider(estado.ambitoMapa)),
            camaraInicial: CamaraMapa(centro: punto, zoom: MapaAlta.zoomCalle),
            zoomMinimo: MapaAlta.zoomMinimo,
            zoomMaximo: MapaAlta.zoomMaximo,
            fondo: ColoresAlta.fondoMapa,
            // Quieto fuera de «Mover el punto»; ahí, con el zoom sobre el centro: el pin está fijo en
            // el centro, así el punto no se corre al acercar o alejar el mapa.
            interaccion: mover ? const InteraccionMapa() : InteraccionMapa.ninguna,
            zoomSobreCentro: true,
            puntos: [
              for (final m in cercanos)
                if (m.ubicacionId != original.id)
                  PuntoMapa(id: m.ubicacionId, coordenadas: m.coordenadas),
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
            alTocar: mover ? widget.alTocar : null,
          ),
        ),
        if (movidos >= MapaModificar.metrosParaFantasma)
          ValueListenableBuilder<CamaraMapa?>(
            valueListenable: _camara,
            builder: (context, camara, _) =>
                _Fantasma(camara: camara, original: original.coordenadas),
          ),
        // El pin fijo en el centro: la punta queda justo en el centro del mapa.
        IgnorePointer(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -22),
              child: const PinAlta(etiqueta: 'Punto de la ubicación'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dónde estaba la ubicación antes de moverla: el pin punteado, su rótulo «Antes» y la línea
/// punteada hasta el pin de ahora (artboard 07·02). Se ubica proyectando el punto guardado con la
/// cámara del mapa; el pin de ahora está en el centro.
class _Fantasma extends StatelessWidget {
  const _Fantasma({required this.camara, required this.original});

  final CamaraMapa? camara;
  final Coordenadas original;

  @override
  Widget build(BuildContext context) {
    final camara = this.camara;
    if (camara == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, caja) {
            final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
            final antes = ProyeccionMercator.aPixeles(original, camara.zoom);
            final puntaAhora = Offset(caja.maxWidth / 2, caja.maxHeight / 2);
            final puntaAntes = puntaAhora + Offset(antes.x - centro.x, antes.y - centro.y);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LineaPunteada(desde: puntaAntes, hasta: puntaAhora),
                  ),
                ),
                // La gota mide 36 × 44 y su punta es el centro de abajo.
                Positioned(
                  left: puntaAntes.dx - 18,
                  top: puntaAntes.dy - 44,
                  child: const PinAlta(
                    colocado: false,
                    etiqueta: 'Dónde estaba la ubicación antes de moverla',
                  ),
                ),
                Positioned(
                  left: puntaAntes.dx,
                  top: puntaAntes.dy + 6,
                  child: const FractionalTranslation(
                    translation: Offset(-.5, 0),
                    child: _RotuloAntes(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RotuloAntes extends StatelessWidget {
  const _RotuloAntes();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x330E1A2B), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: const Text(
        'Antes',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ColoresAlta.tinta),
      ),
    );
  }
}

/// La línea de trazos entre el punto de antes y el de ahora.
class _LineaPunteada extends CustomPainter {
  const _LineaPunteada({required this.desde, required this.hasta});

  final Offset desde;
  final Offset hasta;

  static const _trazo = 6.0;
  static const _hueco = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final largo = (hasta - desde).distance;
    if (!largo.isFinite || largo < 1) return;
    final direccion = (hasta - desde) / largo;
    final pincel = Paint()
      ..color = ColoresAlta.gris
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var d = 0.0; d < largo; d += _trazo + _hueco) {
      canvas.drawLine(
        desde + direccion * d,
        desde + direccion * math.min(d + _trazo, largo),
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(_LineaPunteada anterior) => anterior.desde != desde || anterior.hasta != hasta;
}
