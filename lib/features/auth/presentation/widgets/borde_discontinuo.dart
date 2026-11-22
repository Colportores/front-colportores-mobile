import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Borde de trazos de un rectángulo redondeado (`border: 1.5px dashed` del canvas): Flutter no trae
/// uno. Se pinta por encima del [child], sin ocupar lugar ni tocar su layout.
class BordeDiscontinuo extends StatelessWidget {
  const BordeDiscontinuo({
    super.key,
    required this.color,
    required this.radio,
    required this.child,
    this.grosor = 1.5,
    this.largoTrazo = 5,
    this.largoHueco = 4,
  });

  final Color color;

  /// Radio de las esquinas, igual al del contenedor que se bordea.
  final double radio;
  final double grosor;
  final double largoTrazo;
  final double largoHueco;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _PintorBordeDiscontinuo(
        color: color,
        radio: radio,
        grosor: grosor,
        largoTrazo: largoTrazo,
        largoHueco: largoHueco,
      ),
      child: child,
    );
  }
}

class _PintorBordeDiscontinuo extends CustomPainter {
  const _PintorBordeDiscontinuo({
    required this.color,
    required this.radio,
    required this.grosor,
    required this.largoTrazo,
    required this.largoHueco,
  });

  final Color color;
  final double radio;
  final double grosor;
  final double largoTrazo;
  final double largoHueco;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;
    // El trazo se centra en el contorno: se mete medio grosor para que no se salga del contenedor.
    final contorno = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radio),
    ).deflate(grosor / 2);
    for (final tramo in (Path()..addRRect(contorno)).computeMetrics()) {
      var desde = 0.0;
      while (desde < tramo.length) {
        final hasta = math.min(desde + largoTrazo, tramo.length);
        canvas.drawPath(tramo.extractPath(desde, hasta), pincel);
        desde = hasta + largoHueco;
      }
    }
  }

  @override
  bool shouldRepaint(_PintorBordeDiscontinuo anterior) =>
      anterior.color != color ||
      anterior.radio != radio ||
      anterior.grosor != grosor ||
      anterior.largoTrazo != largoTrazo ||
      anterior.largoHueco != largoHueco;
}
