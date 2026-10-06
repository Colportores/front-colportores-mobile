import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/domain/services/proyeccion_mercator.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/modelo_mapa_base.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_base_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// La vista nativa de `MapaBase` en los tests de widgets: MapLibre no se dibuja en `flutter test`,
/// así que esto la reemplaza (`constructorVistaMapaProvider`) por un recuadro que se comporta como
/// ella en lo que `MapaBase` espera:
///
/// - arrastrar con un dedo mueve el centro; pellizcar con dos cambia el zoom **sobre el punto entre
///   los dedos** (el centro se corre, como en MapLibre);
/// - un toque avisa las coordenadas tocadas;
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

  /// La vista avisa que se movió la cámara a [nueva] y después que quedó quieta, como si un gesto
  /// la hubiera dejado ahí.
  void moverPorGesto(CamaraMapa nueva) {
    camara = nueva;
    _eventos!
      ..camaraMovida(nueva)
      ..camaraQuieta(nueva);
  }

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

  void _alTocar(TapUpDetails d) {
    final centro = ProyeccionMercator.aPixeles(_camara.centro, _camara.zoom);
    final foco = _desdeElCentro(d.localPosition);
    widget.eventos.toque(
      ProyeccionMercator.aCoordenadas(centro.x + foco.dx, centro.y + foco.dy, _camara.zoom),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
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
            child: SizedBox.expand(child: ColoredBox(color: config.fondo)),
          ),
        );
      },
    );
  }
}
