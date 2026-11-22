import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../domain/services/puertos_de_fotos.dart';

/// Las medidas de una imagen sin decodificarla entera; `null` si no es una imagen.
typedef MedirImagen = Future<({int ancho, int alto})?> Function(Uint8List bytes);

/// Recodifica una imagen a JPEG con un tamaño mínimo y una calidad; `null` si no puede.
typedef RecodificarJpeg =
    Future<Uint8List?> Function(
      Uint8List bytes, {
      required int anchoMinimo,
      required int altoMinimo,
      required int calidad,
    });

/// [CompresorDeImagen] sobre `flutter_image_compress` (decisión de Cristian del 03/11 en #169), que
/// comprime en nativo: rápido y sin cargar la foto entera en la memoria de Dart.
///
/// `flutter_image_compress` achica hasta que el lado **menor** llega a su mínimo; la política habla del
/// lado **mayor**. Por eso primero mide la foto y le pide el mínimo que deja el lado mayor en
/// `ladoMaximo` (nunca agranda una foto chica). Endereza la foto según su EXIF y no conserva los
/// metadatos (ni la ubicación de donde se sacó).
final class CompresorFlutterImageCompress implements CompresorDeImagen {
  CompresorFlutterImageCompress({MedirImagen? medir, RecodificarJpeg? recodificar})
    : _medir = medir ?? _medirConUi,
      _recodificar = recodificar ?? _recodificarNativo;

  final MedirImagen _medir;
  final RecodificarJpeg _recodificar;

  @override
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  }) async {
    try {
      final medidas = await _medir(original);
      if (medidas == null || medidas.ancho <= 0 || medidas.alto <= 0) return null;
      final objetivo = medidasObjetivo(medidas.ancho, medidas.alto, ladoMaximo);
      final salida = await _recodificar(
        original,
        anchoMinimo: objetivo.ancho,
        altoMinimo: objetivo.alto,
        calidad: calidad.clamp(1, 100),
      );
      return salida == null || salida.isEmpty ? null : salida;
    } on Object {
      return null;
    }
  }

  /// Las medidas a las que se achica una foto de [ancho] × [alto] para que su lado mayor no pase de
  /// [ladoMaximo], sin agrandarla.
  static ({int ancho, int alto}) medidasObjetivo(int ancho, int alto, int ladoMaximo) {
    final mayor = math.max(ancho, alto);
    if (mayor <= ladoMaximo) return (ancho: ancho, alto: alto);
    final escala = ladoMaximo / mayor;
    return (
      ancho: math.max(1, (ancho * escala).round()),
      alto: math.max(1, (alto * escala).round()),
    );
  }

  static Future<({int ancho, int alto})?> _medirConUi(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final medidas = (ancho: descriptor.width, alto: descriptor.height);
      descriptor.dispose();
      return medidas;
    } finally {
      buffer.dispose();
    }
  }

  static Future<Uint8List?> _recodificarNativo(
    Uint8List bytes, {
    required int anchoMinimo,
    required int altoMinimo,
    required int calidad,
  }) => FlutterImageCompress.compressWithList(
    bytes,
    minWidth: anchoMinimo,
    minHeight: altoMinimo,
    quality: calidad,
  );
}
