import 'dart:async';

import 'package:flutter/services.dart';

import '../../features/mapa/domain/services/marcador_de_telefono.dart';
import 'seguridad_dispositivo_canal.dart';

/// [MarcadorDeTelefono] sobre el canal nativo `colportores/seguridad_dispositivo`, método
/// `marcarTelefono` con `{'numero': ...}`. Del otro lado: `MainActivity.kt`, que abre el marcador del
/// sistema (`ACTION_DIAL`) con el número escrito: la llamada la inicia la colportora, así que no pide
/// ningún permiso. Solo acepta un número de dígitos con un `+` al comienzo.
///
/// Nunca lanza ni registra el número (convenciones §7.5): `false` si no hay con qué marcar (iOS, una
/// tablet) o el sistema no contestó a tiempo.
final class MarcadorDeTelefonoCanal implements MarcadorDeTelefono {
  MarcadorDeTelefonoCanal({MethodChannel? canal, this.tiempoMaximo = const Duration(seconds: 5)})
    : _canal = canal ?? const MethodChannel(SeguridadDispositivoCanal.nombre);

  /// Cuánto se espera la respuesta de la plataforma antes de dar por fallida la apertura.
  final Duration tiempoMaximo;

  final MethodChannel _canal;

  @override
  Future<bool> marcar(String numero) async {
    try {
      final abierto = await _canal
          .invokeMethod<bool>('marcarTelefono', {'numero': numero})
          .timeout(tiempoMaximo);
      return abierto ?? false;
    } on Exception {
      // `PlatformException`, `MissingPluginException` (iOS) o `TimeoutException`.
      return false;
    }
  }
}
