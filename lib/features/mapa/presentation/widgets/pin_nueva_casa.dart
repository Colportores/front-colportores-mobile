import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../textos_alta_por_pin.dart';
import 'piezas_alta.dart';

/// Las claves con que los tests (y el QA) encuentran las piezas del pin de la casa nueva.
abstract final class ClavesPinNuevaCasa {
  static const boton = Key('pin_nueva_casa_boton');
  static const enArrastre = Key('pin_nueva_casa_en_arrastre');
  static const puesto = Key('pin_nueva_casa_puesto');
  static const posicion = Key('pin_nueva_casa_posicion');
  static const confirmar = Key('pin_nueva_casa_confirmar');
  static const cancelar = Key('pin_nueva_casa_cancelar');
  static const direccion = Key('pin_nueva_casa_direccion');
  static const queHayAca = Key('pin_nueva_casa_que_hay_aca');
  static const seguir = Key('pin_nueva_casa_seguir');
  static const volver = Key('pin_nueva_casa_volver');
  static const campoNumero = Key('pin_nueva_casa_numero');
  static const campoCalle = Key('pin_nueva_casa_calle');
  static const falla = Key('pin_nueva_casa_falla');
  static const registrando = Key('pin_nueva_casa_registrando');
  static Key tipo(String nombre) => Key('pin_nueva_casa_tipo_$nombre');
}

/// El lado del círculo del pin de la casa nueva (el «nw» del canvas: círculo blanco con borde navy
/// punteado y un «+»). El canvas lo dibuja de 22; acá mide lo del marcador seleccionado (36) para que
/// se vea y se pueda agarrar.
const ladoPinCasaNueva = 36.0;

/// El área que responde al dedo: un objetivo táctil de 48 dp aunque el círculo mida menos.
const ladoToquePinCasaNueva = 48.0;

/// El pin de la casa nueva (vista 39, «nw»): un círculo blanco con borde navy punteado de 3 dp y un «+».
class CirculoCasaNueva extends StatelessWidget {
  const CirculoCasaNueva({super.key, this.levantado = false});

  /// Se lo está llevando con el dedo: la sombra es más grande.
  final bool levantado;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: Container(
        width: ladoPinCasaNueva,
        height: ladoPinCasaNueva,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0x590E1A2B),
              blurRadius: levantado ? 14 : 6,
              offset: Offset(0, levantado ? 8 : 2),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _BordePunteadoCirculo(color: navy),
          child: Center(
            child: Text(
              '+',
              textScaler: TextScaler.noScaling,
              style: TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w700, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _BordePunteadoCirculo extends CustomPainter {
  const _BordePunteadoCirculo({required this.color});

  final Color color;

  static const _grosor = 3.0;
  static const _trazo = 6.0;
  static const _hueco = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final radio = (size.shortestSide - _grosor) / 2;
    final circulo = Path()
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: radio));
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _grosor;
    for (final tramo in circulo.computeMetrics()) {
      for (var d = 0.0; d < tramo.length; d += _trazo + _hueco) {
        canvas.drawPath(tramo.extractPath(d, math.min(d + _trazo, tramo.length)), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_BordePunteadoCirculo anterior) => anterior.color != color;
}

/// El pin que se lleva con el dedo desde el botón hasta el mapa (la cabeza del arrastre).
class PinEnArrastre extends StatelessWidget {
  const PinEnArrastre({super.key});

  @override
  Widget build(BuildContext context) => const CirculoCasaNueva(levantado: true);
}

/// El pin de la casa nueva ya soltado en el mapa (N·01): cae y queda donde se lo soltó, y se lo puede
/// llevar a otro lado arrastrándolo. Es un widget encima del mapa, no una capa del estilo: el mapa
/// nativo no deja arrastrar un marcador.
class PinSobreElMapa extends StatefulWidget {
  const PinSobreElMapa({
    super.key,
    required this.alMover,
    required this.alSoltar,
    this.cae = true,
    this.deshabilitado = false,
  });

  /// Cuánto se corrió el dedo desde el último aviso.
  final ValueChanged<Offset> alMover;
  final VoidCallback alSoltar;

  /// El pin cae al aparecer (~0,6 s, como el canvas: «al soltar, el pin cae»).
  final bool cae;

  /// Mientras se registra no se mueve: el punto que se guarda es el que se ve.
  final bool deshabilitado;

  /// Cuánto cae el pin al aparecer: lo que el arrastre lo levanta sobre el dedo.
  static const alturaDeLaCaida = 24.0;

  @override
  State<PinSobreElMapa> createState() => _PinSobreElMapaState();
}

class _PinSobreElMapaState extends State<PinSobreElMapa> with SingleTickerProviderStateMixin {
  late final AnimationController _caida = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _curva = CurvedAnimation(parent: _caida, curve: Curves.bounceOut);
  var _llevandolo = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_caida.status == AnimationStatus.dismissed) {
      final sinMovimiento = MediaQuery.disableAnimationsOf(context);
      if (widget.cae && !sinMovimiento) {
        unawaited(_caida.forward());
      } else {
        _caida.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _caida.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ClavesPinNuevaCasa.puesto,
      container: true,
      label: TextosAltaPorPin.pinDeLaCasaNueva,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Desde el apoyo del dedo: el pin acompaña todo el recorrido, no solo lo que pasa del umbral.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: widget.deshabilitado ? null : (_) => setState(() => _llevandolo = true),
        onPanUpdate: widget.deshabilitado ? null : (d) => widget.alMover(d.delta),
        onPanEnd: widget.deshabilitado
            ? null
            : (_) {
                setState(() => _llevandolo = false);
                widget.alSoltar();
              },
        onPanCancel: widget.deshabilitado
            ? null
            : () {
                if (!_llevandolo) return;
                setState(() => _llevandolo = false);
                widget.alSoltar();
              },
        child: SizedBox(
          width: ladoToquePinCasaNueva,
          height: ladoToquePinCasaNueva,
          child: AnimatedBuilder(
            animation: _curva,
            builder: (context, hijo) => Transform.translate(
              offset: Offset(0, -(1 - _curva.value) * PinSobreElMapa.alturaDeLaCaida),
              child: hijo,
            ),
            child: Center(child: CirculoCasaNueva(levantado: _llevandolo)),
          ),
        ),
      ),
    );
  }
}

/// El botón del pin de abajo a la derecha (vista 39, M·01): un círculo navy de 52 dp con la mira, y
/// su leyenda «Arrastrá para sumar una casa». Se arrastra al mapa; **tocarlo** lo deja en el centro
/// del mapa (la alternativa a arrastrar: WCAG 2.5.7).
class BotonPinNuevaCasa extends StatelessWidget {
  const BotonPinNuevaCasa({
    super.key,
    required this.alEmpezar,
    required this.alMover,
    required this.alSoltar,
    required this.alCancelar,
    required this.alTocar,
  });

  /// El dedo empezó a llevar el pin: dónde está, en coordenadas de la pantalla.
  final ValueChanged<Offset> alEmpezar;
  final ValueChanged<Offset> alMover;

  /// Soltó el dedo: quien lo recibe sabe dónde estaba por el último [alMover].
  final VoidCallback alSoltar;
  final VoidCallback alCancelar;
  final VoidCallback alTocar;

  /// El lado del círculo.
  static const lado = 52.0;

  static const _anchoMaximoLeyenda = 190.0;
  static const _rellenoLeyenda = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
  static const _estiloLeyenda = TextStyle(
    fontSize: 12.5,
    height: 1.3,
    color: ColoresAlta.tinta,
    fontWeight: FontWeight.w600,
  );

  /// La leyenda se dibuja hasta el 150 % de texto. Más grande, ocuparía una columna entera de alto y
  /// le sacaría lugar al mapa y a los avisos en un teléfono chico: queda el círculo, con su nombre
  /// completo para el lector de pantalla y el toque como alternativa al arrastre.
  static bool conLeyenda(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) <= 15;

  /// Cuánto mide de alto la pieza entera: el círculo, o la leyenda de al lado si con el texto del
  /// teléfono ocupa más renglones y es más alta. La pantalla del mapa lo necesita para dejarle lugar.
  static double alto(BuildContext context) {
    if (!conLeyenda(context)) return lado;
    final estilo = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).merge(
      _estiloLeyenda,
    );
    final medida = TextPainter(
      text: TextSpan(text: TextosAltaPorPin.pinLeyenda, style: estilo),
      textDirection: Directionality.of(context),
      textAlign: TextAlign.center,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: _anchoMaximoLeyenda - _rellenoLeyenda.horizontal);
    final leyenda = medida.height + _rellenoLeyenda.vertical;
    medida.dispose();
    return math.max(lado, leyenda);
  }

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    final conLeyenda = BotonPinNuevaCasa.conLeyenda(context);
    return Semantics(
      container: true,
      button: true,
      label: TextosAltaPorPin.pin,
      onTap: alTocar,
      child: ExcludeSemantics(
        // Toda la pieza (la leyenda y el círculo) lleva el dedo: tocarla o arrastrarla desde cualquier
        // parte es lo mismo, y el objetivo es más grande que los 52 dp del círculo.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: alTocar,
          onPanStart: (d) => alEmpezar(d.globalPosition),
          onPanUpdate: (d) => alMover(d.globalPosition),
          onPanEnd: (_) => alSoltar(),
          onPanCancel: alCancelar,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (conLeyenda) ...[
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _anchoMaximoLeyenda),
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding: _rellenoLeyenda,
                        child: Text(
                          TextosAltaPorPin.pinLeyenda,
                          textAlign: TextAlign.center,
                          style: _estiloLeyenda,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Material(
                key: ClavesPinNuevaCasa.boton,
                color: navy,
                elevation: 4,
                shape: const CircleBorder(),
                child: const SizedBox(
                  width: lado,
                  height: lado,
                  child: Icon(Icons.gps_fixed, size: 24, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
