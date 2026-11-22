import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'seguridad_dispositivo_canal.dart';

/// Abre un enlace fuera de la app: «Contactar a soporte» de la vista 13 (#222) abre el chat de
/// WhatsApp de soporte.
///
/// Puerto en Dart puro: la implementación de producción es [AbridorEnlaceCanal]; los tests usan un
/// fake. Nunca lanza: devuelve `false` si no hay nada en el teléfono que pueda abrirlo, y la UI le
/// dice al usuario cómo contactar a soporte a mano.
abstract interface class AbridorEnlaceExterno {
  /// `true` si el sistema encontró con qué abrir [enlace]. Con WhatsApp instalado abre el chat; sin
  /// él, `wa.me` se abre en el navegador, que ofrece instalarlo o usar la versión web.
  Future<bool> abrir(Uri enlace);
}

/// [AbridorEnlaceExterno] sobre el canal nativo `colportores/seguridad_dispositivo`, método
/// `abrirEnlace` con `{'url': ...}`. Del otro lado: `MainActivity.kt`, que solo acepta `https` de
/// `wa.me`.
final class AbridorEnlaceCanal implements AbridorEnlaceExterno {
  AbridorEnlaceCanal({MethodChannel? canal, this.tiempoMaximo = const Duration(seconds: 5)})
    : _canal = canal ?? const MethodChannel(SeguridadDispositivoCanal.nombre);

  /// Cuánto se espera la respuesta de la plataforma antes de dar por fallida la apertura.
  final Duration tiempoMaximo;

  final MethodChannel _canal;

  @override
  Future<bool> abrir(Uri enlace) async {
    try {
      final abierto = await _canal
          .invokeMethod<bool>('abrirEnlace', {'url': enlace.toString()})
          .timeout(tiempoMaximo);
      return abierto ?? false;
    } on Exception {
      // `PlatformException`, `MissingPluginException` (iOS) o `TimeoutException`.
      return false;
    }
  }
}

/// El abridor de enlaces de la app. Sin estado: los tests lo reemplazan con un fake.
final abridorEnlaceExternoProvider = Provider<AbridorEnlaceExterno>((ref) => AbridorEnlaceCanal());
