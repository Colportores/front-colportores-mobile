import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'modelo_mapa_base.dart' show ColoresMapa;

/// La etiqueta de «cerca tuyo» (canvas 06C·01 y «Referencias»: «Cerca tuyo: crece y muestra el
/// número»): una píldora blanca con borde del color del estado, el círculo del estado a la izquierda,
/// el número de puerta en JetBrains Mono y una punta abajo que marca el lugar exacto.
///
/// El mapa nativo no dibuja widgets: la etiqueta se pinta una vez por número (son pocas, solo las
/// ubicaciones a menos de 60 m del GPS) en una imagen que la vista registra en el estilo, y una capa
/// de símbolos la pone en cada punto, anclada por la punta (`icon-anchor: bottom`).
///
/// Hoy todas las ubicaciones están «Sin visita» (los colores y glifos por estado llegan con
/// HU-VIS-005): borde y círculo grises (`#6B7688`), el círculo vacío. Las medidas son las del canvas,
/// en dp.
abstract final class MarcadorCercano {
  /// Alto de la píldora, borde incluido.
  static const altoPildora = 32.0;

  /// Grosor del borde de la píldora.
  static const borde = 2.0;

  /// Lo que hay entre el borde y el círculo a la izquierda, y entre el número y el borde a la
  /// derecha.
  static const relleno = 4.0;
  static const rellenoDerecho = 9.0;

  /// El círculo del estado: diámetro y grosor de su borde (el de «Sin visita» va vacío).
  static const diametroCirculo = 22.0;
  static const bordeCirculo = 2.5;

  /// Entre el círculo y el número.
  static const separacion = 5.0;

  /// El tamaño del número de puerta.
  static const tamanoNumero = 13.5;

  /// La punta de abajo: ancho (6 a cada lado del centro) y alto.
  static const anchoPunta = 12.0;
  static const altoPunta = 7.0;

  /// Aire alrededor de la píldora para la sombra (canvas: `0 2px 6px`): arriba y a los lados.
  static const margenSombra = 8.0;

  /// El nombre con que la imagen de la etiqueta de [etiqueta] se registra en el estilo.
  static String nombre(String etiqueta) => 'colportores:cercano:$etiqueta';

  /// El color del borde, la punta y el círculo del estado «Sin visita».
  static const colorEstado = ColoresMapa.bordeContexto;

  static const _tinta = ColoresMapa.tintaOscura;

  /// Lo que mide la imagen de [etiqueta] en dp: la píldora con su sombra y la punta. El de abajo
  /// de la imagen es la punta, así que el ancla `bottom` cae sobre la ubicación.
  static ui.Size medidas(String etiqueta) {
    final texto = _texto(etiqueta);
    final ancho = texto.width;
    texto.dispose();
    return _medidas(ancho);
  }

  static ui.Size _medidas(double anchoTexto) =>
      ui.Size(_anchoPildora(anchoTexto) + 2 * margenSombra, margenSombra + altoPildora + altoPunta);

  static double _anchoPildora(double anchoTexto) =>
      borde + relleno + diametroCirculo + separacion + anchoTexto + rellenoDerecho + borde;

  static TextPainter _texto(String etiqueta) => TextPainter(
    text: TextSpan(
      text: etiqueta,
      style: const TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: tamanoNumero,
        fontWeight: FontWeight.w500,
        color: _tinta,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  /// La etiqueta de [etiqueta] como PNG, con [escala] píxeles por dp (la imagen mide
  /// `medidas(etiqueta) * escala`): el mapa nativo la muestra con su tamaño en dp si [escala] es la
  /// de la pantalla.
  static Future<Uint8List> dibujar(String etiqueta, {double escala = 1}) async {
    final texto = _texto(etiqueta);
    final ui.Image imagen;
    try {
      imagen = await _pintar(texto, escala);
    } finally {
      texto.dispose();
    }
    try {
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      if (datos == null) throw StateError('no se pudo codificar la etiqueta');
      return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
    } finally {
      imagen.dispose();
    }
  }

  static Future<ui.Image> _pintar(TextPainter texto, double escala) {
    final medida = _medidas(texto.width);
    final ancho = (medida.width * escala).ceil();
    final alto = (medida.height * escala).ceil();

    final grabador = ui.PictureRecorder();
    final lienzo = ui.Canvas(grabador)..scale(escala);

    final anchoPildora = _anchoPildora(texto.width);
    final pildora = ui.Rect.fromLTWH(margenSombra, margenSombra, anchoPildora, altoPildora);
    final exterior = ui.RRect.fromRectAndRadius(pildora, const ui.Radius.circular(altoPildora / 2));

    // La sombra del canvas: `0 2px 6px rgba(14,26,43,.3)`.
    lienzo.drawRRect(
      exterior.shift(const ui.Offset(0, 2)),
      ui.Paint()
        ..color = const ui.Color(0x4D0E1A2B)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    // El borde y, adentro, el blanco.
    lienzo
      ..drawRRect(exterior, ui.Paint()..color = colorEstado)
      ..drawRRect(exterior.deflate(borde), ui.Paint()..color = const ui.Color(0xFFFFFFFF));

    // El círculo del estado, vacío («Sin visita»).
    final centroCirculo = ui.Offset(
      pildora.left + borde + relleno + diametroCirculo / 2,
      pildora.center.dy,
    );
    lienzo
      ..drawCircle(centroCirculo, diametroCirculo / 2, ui.Paint()..color = colorEstado)
      ..drawCircle(
        centroCirculo,
        diametroCirculo / 2 - bordeCirculo,
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );

    // El número de puerta.
    texto.paint(
      lienzo,
      ui.Offset(
        centroCirculo.dx + diametroCirculo / 2 + separacion,
        pildora.center.dy - texto.height / 2,
      ),
    );

    // La punta, pegada al borde de abajo y centrada.
    final x = pildora.center.dx;
    lienzo.drawPath(
      ui.Path()
        ..moveTo(x - anchoPunta / 2, pildora.bottom)
        ..lineTo(x + anchoPunta / 2, pildora.bottom)
        ..lineTo(x, pildora.bottom + altoPunta)
        ..close(),
      ui.Paint()..color = colorEstado,
    );

    return grabador.endRecording().toImage(ancho, alto);
  }
}
