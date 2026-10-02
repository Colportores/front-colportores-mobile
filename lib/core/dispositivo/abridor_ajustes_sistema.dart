import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'seguridad_dispositivo_canal.dart';

/// Abre pantallas de los ajustes del sistema desde la app: «Abrir Ajustes» (bloqueo de pantalla) y
/// «Abrir almacenamiento» de la vista 13 (#222).
///
/// Puerto en Dart puro: la implementación de producción es [AbridorAjustesCanal]; los tests usan un
/// fake. Nunca lanza: devuelve `false` si la plataforma no pudo abrir la pantalla (iOS no tiene
/// equivalente, o un equipo sin esa pantalla), y la UI le dice al usuario cómo llegar a mano.
abstract interface class AbridorAjustesSistema {
  /// Ajustes de seguridad, donde se configura el bloqueo de pantalla.
  Future<bool> abrirSeguridad();

  /// Ajustes de almacenamiento, para liberar espacio.
  Future<bool> abrirAlmacenamiento();
}

/// [AbridorAjustesSistema] sobre el canal nativo `colportores/seguridad_dispositivo` (el mismo de
/// [SeguridadDispositivoCanal]), con los métodos `abrirAjustesSeguridad` y
/// `abrirAjustesAlmacenamiento`. Del otro lado: `MainActivity.kt`.
final class AbridorAjustesCanal implements AbridorAjustesSistema {
  AbridorAjustesCanal({MethodChannel? canal, this.tiempoMaximo = const Duration(seconds: 5)})
    : _canal = canal ?? const MethodChannel(SeguridadDispositivoCanal.nombre);

  /// Cuánto se espera la respuesta de la plataforma antes de dar por fallida la apertura.
  final Duration tiempoMaximo;

  final MethodChannel _canal;

  @override
  Future<bool> abrirSeguridad() => _abrir('abrirAjustesSeguridad');

  @override
  Future<bool> abrirAlmacenamiento() => _abrir('abrirAjustesAlmacenamiento');

  Future<bool> _abrir(String metodo) async {
    try {
      final abierta = await _canal.invokeMethod<bool>(metodo).timeout(tiempoMaximo);
      return abierta ?? false;
    } on Exception {
      // `PlatformException`, `MissingPluginException` (iOS) o `TimeoutException`.
      return false;
    }
  }
}

/// El abridor de ajustes de la app. Sin estado y con el canal real por defecto: los tests lo
/// reemplazan con un fake.
final abridorAjustesSistemaProvider = Provider<AbridorAjustesSistema>(
  (ref) => AbridorAjustesCanal(),
);
