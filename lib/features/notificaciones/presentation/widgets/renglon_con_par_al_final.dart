import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Un renglón con un [titulo] a la izquierda y un [par] a la derecha (por ejemplo la hora de un
/// aviso con su `›`).
///
/// Si el par entra al lado del título, quedan en el mismo renglón, centrados en vertical y con el par
/// pegado al borde derecho. Si no entra (letra al 200 %), el par **baja entero**, alineado a la
/// derecha y sin recortarse: nada se parte ni se corta. A diferencia de un `Wrap`, el par que queda
/// solo en su renglón sigue a la derecha (un `Wrap` con `spaceBetween` lo manda a la izquierda).
class RenglonConParAlFinal extends MultiChildRenderObjectWidget {
  RenglonConParAlFinal({
    super.key,
    required Widget titulo,
    required Widget par,
    this.anchoMaximoDelTitulo = double.infinity,
    this.separacion = 12,
    this.separacionVertical = 4,
  }) : super(children: [titulo, par]);

  /// Lo más ancho que puede ser el título (el resto del renglón es para el par).
  final double anchoMaximoDelTitulo;

  /// El espacio entre el título y el par cuando van en el mismo renglón.
  final double separacion;

  /// El espacio entre el título y el par cuando el par baja.
  final double separacionVertical;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderRenglonConParAlFinal(anchoMaximoDelTitulo, separacion, separacionVertical);

  @override
  void updateRenderObject(BuildContext context, covariant RenderRenglonConParAlFinal renderObject) {
    renderObject
      ..anchoMaximoDelTitulo = anchoMaximoDelTitulo
      ..separacion = separacion
      ..separacionVertical = separacionVertical;
  }
}

class _DatosDelHijo extends ContainerBoxParentData<RenderBox> {}

/// La caja de [RenglonConParAlFinal]: dos hijos, el título y el par.
class RenderRenglonConParAlFinal extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DatosDelHijo>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DatosDelHijo> {
  RenderRenglonConParAlFinal(
    this._anchoMaximoDelTitulo,
    this._separacion,
    this._separacionVertical,
  );

  double _anchoMaximoDelTitulo;
  double get anchoMaximoDelTitulo => _anchoMaximoDelTitulo;
  set anchoMaximoDelTitulo(double v) {
    if (v == _anchoMaximoDelTitulo) return;
    _anchoMaximoDelTitulo = v;
    markNeedsLayout();
  }

  double _separacion;
  double get separacion => _separacion;
  set separacion(double v) {
    if (v == _separacion) return;
    _separacion = v;
    markNeedsLayout();
  }

  double _separacionVertical;
  double get separacionVertical => _separacionVertical;
  set separacionVertical(double v) {
    if (v == _separacionVertical) return;
    _separacionVertical = v;
    markNeedsLayout();
  }

  RenderBox get _titulo => firstChild!;
  RenderBox get _par => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DatosDelHijo) child.parentData = _DatosDelHijo();
  }

  /// Mide y ubica todo; con [ensayo] solo devuelve el tamaño (sin tocar los hijos).
  ({Size tamano, Offset posTitulo, Offset posPar}) _acomodar(
    BoxConstraints constraints, {
    required bool ensayo,
  }) {
    final maxAncho = constraints.maxWidth;
    final sueltas = BoxConstraints(maxWidth: maxAncho);
    final tituloMax = BoxConstraints(maxWidth: math.min(maxAncho, _anchoMaximoDelTitulo));

    Size medir(RenderBox hijo, BoxConstraints c) =>
        ensayo ? hijo.getDryLayout(c) : (hijo..layout(c, parentUsesSize: true)).size;

    final par = medir(_par, sueltas);
    final titulo = medir(_titulo, tituloMax);
    final entra = titulo.width + _separacion + par.width <= maxAncho;

    final double ancho;
    final double alto;
    final Offset posTitulo;
    final Offset posPar;
    if (entra) {
      alto = math.max(titulo.height, par.height);
      ancho = maxAncho.isFinite ? maxAncho : titulo.width + _separacion + par.width;
      posTitulo = Offset(0, (alto - titulo.height) / 2);
      posPar = Offset(ancho - par.width, (alto - par.height) / 2);
    } else {
      alto = titulo.height + _separacionVertical + par.height;
      ancho = maxAncho.isFinite ? maxAncho : math.max(titulo.width, par.width);
      posTitulo = Offset.zero;
      posPar = Offset(ancho - par.width, titulo.height + _separacionVertical);
    }
    return (tamano: constraints.constrain(Size(ancho, alto)), posTitulo: posTitulo, posPar: posPar);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _acomodar(constraints, ensayo: true).tamano;

  @override
  void performLayout() {
    final r = _acomodar(constraints, ensayo: false);
    size = r.tamano;
    (_titulo.parentData! as _DatosDelHijo).offset = r.posTitulo;
    (_par.parentData! as _DatosDelHijo).offset = r.posPar;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(_titulo.getMinIntrinsicWidth(height), _par.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.min(_titulo.getMaxIntrinsicWidth(height), _anchoMaximoDelTitulo) +
      _separacion +
      _par.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _alturaPara(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _alturaPara(width);

  double _alturaPara(double width) {
    final altoTitulo = _titulo.getMinIntrinsicHeight(math.min(width, _anchoMaximoDelTitulo));
    final altoPar = _par.getMinIntrinsicHeight(width);
    final anchoTitulo = math.min(
      _titulo.getMaxIntrinsicWidth(double.infinity),
      math.min(width, _anchoMaximoDelTitulo),
    );
    final anchoPar = _par.getMaxIntrinsicWidth(double.infinity);
    return anchoTitulo + _separacion + anchoPar <= width
        ? math.max(altoTitulo, altoPar)
        : altoTitulo + _separacionVertical + altoPar;
  }
}
