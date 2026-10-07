import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_base_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/situacion_mapa_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Los overrides con que la pestaña «Mapa» de la pantalla principal se arma sin plugins: la vista
/// falsa de [FabricaMapaFalsa] y un mapa sin tiles ni aviso. Los tests que abren esa pestaña de
/// pasada (sin probar el mapa) los suman a los suyos.
List<Override> overridesPestanaMapa([FabricaMapaFalsa? mapa]) => [
  (mapa ?? FabricaMapaFalsa()).override,
  situacionMapaProvider.overrideWith(
    (ref, ambito) => const SituacionMapa(fuente: FuenteMapa.sinTiles()),
  ),
];

/// La vista nativa de `MapaBase` en los tests de widgets: MapLibre no se dibuja en `flutter test`,
/// así que esto la reemplaza (`constructorVistaMapaProvider`) por un recuadro que se comporta como
/// ella en lo que `MapaBase` espera:
///
/// - arrastrar con un dedo mueve el centro; pellizcar con dos cambia el zoom **sobre el punto entre
///   los dedos** (el centro se corre, como en MapLibre);
/// - un toque avisa las coordenadas tocadas (con el doble toque prendido, pasado el plazo del doble
///   toque, como la nativa: ahí un toque se confirma recién al no venir otro);
/// - mantener el dedo apoyado (500 ms) avisa un toque largo en las coordenadas tocadas, y el toque
///   corto de ese gesto no se avisa;
/// - con `dobleToqueZoom`, un doble toque acerca un nivel **sobre el punto tocado**, animado, y el
///   centro se corre como en MapLibre;
/// - un `moverCamara` deja la cámara ahí y responde como MapLibre: un movimiento de cámara y que
///   quedó quieta.
///
/// Todo lo que dibujaría la vista (fuente de tiles, puntos, radio de precisión) queda en [config].
final class FabricaMapaFalsa {
  /// La última configuración con que `MapaBase` armó la vista; `null` si todavía no la armó.
  ConfigVistaMapa? config;

  /// La cámara de la vista: la inicial, lo que movieron los gestos y los `moverCamara`.
  CamaraMapa? camara;

  /// Cada cámara que `MapaBase` le pidió a la vista (`moverCamara`), en orden.
  final movimientos = <CamaraMapa>[];

  /// La vista avisa un movimiento y que quedó quieta después de cada `moverCamara`, como la nativa.
  bool ecoDeMoverCamara = true;

  /// Si no es `null`, cada `moverCamara` lo lanza (la vista nativa no pudo mover la cámara).
  Object? fallaAlMover;

  /// El doble toque acerca (animado). En `false` no pasa nada, como con el zoom ya en el máximo: la
  /// vista nativa no manda ninguna cámara.
  bool dobleToqueAnima = true;

  EventosVistaMapa? _eventos;

  /// ¿Hay una vista armada?
  bool get armada => config != null;

  /// El `ConstructorVistaMapa` de [constructorVistaMapaProvider].
  Widget construir(BuildContext context, ConfigVistaMapa config, EventosVistaMapa eventos) {
    this.config = config;
    _eventos = eventos;
    return VistaMapaFalsa(fabrica: this, config: config, eventos: eventos);
  }

  /// Un toque simulado en [coordenadas], sin gesto de por medio.
  void tocar(Coordenadas coordenadas) => _eventos!.toque(coordenadas);

  /// Un punto tocado simulado.
  void tocarPunto(String id) => _eventos!.toquePunto(id);

  /// Un toque largo simulado en [coordenadas], sin gesto de por medio.
  void tocarLargo(Coordenadas coordenadas) => _eventos!.toqueLargo(coordenadas);

  /// La vista avisa que se movió la cámara a [nueva] y después que quedó quieta, como si un gesto
  /// la hubiera dejado ahí.
  void moverPorGesto(CamaraMapa nueva) {
    camara = nueva;
    _eventos!
      ..camaraMovida(nueva)
      ..camaraQuieta(nueva);
  }

  /// La vista avisa un movimiento de cámara y todavía no que quedó quieta (el gesto sigue).
  void moverSinTerminar(CamaraMapa nueva) {
    camara = nueva;
    _eventos!.camaraMovida(nueva);
  }

  /// La vista avisa que la cámara quedó quieta donde está, sin que se haya movido.
  void avisarQuieta() => _eventos!.camaraQuieta(camara!);

  /// Los overrides que meten esta vista en el árbol.
  Override get override => constructorVistaMapaProvider.overrideWithValue(construir);
}

class VistaMapaFalsa extends StatefulWidget {
  const VistaMapaFalsa({
    super.key,
    required this.fabrica,
    required this.config,
    required this.eventos,
  });

  final FabricaMapaFalsa fabrica;
  final ConfigVistaMapa config;
  final EventosVistaMapa eventos;

  @override
  State<VistaMapaFalsa> createState() => _VistaMapaFalsaState();
}

class _VistaMapaFalsaState extends State<VistaMapaFalsa> implements PuertoVistaMapa {
  late CamaraMapa _camara = widget.fabrica.camara ?? widget.config.camaraInicial;
  var _tamano = Size.zero;
  var _focoPrevio = Offset.zero;
  var _escalaPrevia = 1.0;
  var _puntoDelDobleToque = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.fabrica.camara = _camara;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.eventos.listo(this);
    });
  }

  @override
  void didUpdateWidget(VistaMapaFalsa anterior) {
    super.didUpdateWidget(anterior);
    widget.fabrica.config = widget.config;
  }

  @override
  Future<void> moverCamara(CamaraMapa camara) async {
    widget.fabrica.movimientos.add(camara);
    final falla = widget.fabrica.fallaAlMover;
    if (falla != null) throw falla;
    _poner(camara);
    if (!widget.fabrica.ecoDeMoverCamara) return;
    // La vista nativa responde por el canal de la plataforma, nunca en medio de un build.
    await Future<void>.value();
    if (!mounted) return;
    widget.eventos
      ..camaraMovida(camara)
      ..camaraQuieta(camara);
  }

  void _poner(CamaraMapa camara) {
    _camara = camara;
    widget.fabrica.camara = camara;
  }

  Offset _desdeElCentro(Offset local) => local - Offset(_tamano.width / 2, _tamano.height / 2);

  void _alEmpezar(ScaleStartDetails d) {
    _focoPrevio = _desdeElCentro(d.localFocalPoint);
    _escalaPrevia = 1;
  }

  void _alActualizar(ScaleUpdateDetails d) {
    final config = widget.config;
    final foco = config.interaccion.desplazar ? _desdeElCentro(d.localFocalPoint) : _focoPrevio;
    var zoom = _camara.zoom;
    if (d.pointerCount >= 2 && config.interaccion.zoom && _escalaPrevia > 0) {
      zoom += math.log(d.scale / _escalaPrevia) / math.ln2;
      zoom = zoom.clamp(config.zoomMinimo, config.zoomMaximo);
    }
    _escalaPrevia = d.scale;
    // El punto que estaba bajo los dedos sigue bajo los dedos.
    final centroViejo = ProyeccionMercator.aPixeles(_camara.centro, _camara.zoom);
    final bajoLosDedos = ProyeccionMercator.aCoordenadas(
      centroViejo.x + _focoPrevio.dx,
      centroViejo.y + _focoPrevio.dy,
      _camara.zoom,
    );
    final nuevo = ProyeccionMercator.aPixeles(bajoLosDedos, zoom);
    final centro = ProyeccionMercator.aCoordenadas(nuevo.x - foco.dx, nuevo.y - foco.dy, zoom);
    _focoPrevio = foco;
    final camara = CamaraMapa(centro: centro, zoom: zoom);
    _poner(camara);
    widget.eventos.camaraMovida(camara);
  }

  void _alTerminar(ScaleEndDetails d) => widget.eventos.camaraQuieta(_camara);

  /// El doble toque de MapLibre: un nivel más de zoom, animado (unos 300 ms), sobre el punto tocado.
  Future<void> _alDobleToque() async {
    if (!widget.fabrica.dobleToqueAnima) return;
    final config = widget.config;
    final inicio = _camara;
    final zoomFinal = (inicio.zoom + 1).clamp(config.zoomMinimo, config.zoomMaximo);
    final foco = _desdeElCentro(_puntoDelDobleToque);
    final centroInicio = ProyeccionMercator.aPixeles(inicio.centro, inicio.zoom);
    final bajoElDedo = ProyeccionMercator.aCoordenadas(
      centroInicio.x + foco.dx,
      centroInicio.y + foco.dy,
      inicio.zoom,
    );
    const pasos = 4;
    for (var i = 1; i <= pasos; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 75));
      if (!mounted) return;
      final zoom = inicio.zoom + (zoomFinal - inicio.zoom) * i / pasos;
      final enMundo = ProyeccionMercator.aPixeles(bajoElDedo, zoom);
      final camara = CamaraMapa(
        centro: ProyeccionMercator.aCoordenadas(enMundo.x - foco.dx, enMundo.y - foco.dy, zoom),
        zoom: zoom,
      );
      _poner(camara);
      widget.eventos.camaraMovida(camara);
    }
    widget.eventos.camaraQuieta(_camara);
  }

  Coordenadas _coordenadasDe(Offset local) {
    final centro = ProyeccionMercator.aPixeles(_camara.centro, _camara.zoom);
    final foco = _desdeElCentro(local);
    return ProyeccionMercator.aCoordenadas(centro.x + foco.dx, centro.y + foco.dy, _camara.zoom);
  }

  void _alTocar(TapUpDetails d) => widget.eventos.toque(_coordenadasDe(d.localPosition));

  void _alTocarLargo(LongPressStartDetails d) =>
      widget.eventos.toqueLargo(_coordenadasDe(d.localPosition));

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final conDobleToque = config.dobleToqueZoom && config.interaccion.zoom;
    return LayoutBuilder(
      builder: (context, restricciones) {
        _tamano = restricciones.biggest;
        // La vista nativa no aporta nodos de accesibilidad de Flutter.
        return ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: config.interaccion.hay ? _alEmpezar : null,
            onScaleUpdate: config.interaccion.hay ? _alActualizar : null,
            onScaleEnd: config.interaccion.hay ? _alTerminar : null,
            onTapUp: _alTocar,
            onLongPressStart: _alTocarLargo,
            onDoubleTapDown: conDobleToque ? (d) => _puntoDelDobleToque = d.localPosition : null,
            onDoubleTap: conDobleToque ? _alDobleToque : null,
            child: SizedBox.expand(child: ColoredBox(color: config.fondo)),
          ),
        );
      },
    );
  }
}
