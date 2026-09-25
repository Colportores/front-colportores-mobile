import 'package:flutter/services.dart';

import 'seguridad_dispositivo.dart';

/// [SeguridadDispositivo] sobre el canal nativo `colportores/seguridad_dispositivo`.
///
/// Del otro lado: `MainActivity.kt` en Android y `AppDelegate.swift` en iOS. Los dos exponen
/// `bloqueoPantalla` (→ `bool`) y `nivelAlmacen` (→ `"hardware"` o `"software"`). Es un canal chico
/// y propio a propósito (ADR-006, S10): lo que pregunta no lo cubre `flutter_secure_storage`.
///
/// Toda falla de la plataforma (`PlatformException`, `MissingPluginException`, una respuesta que
/// no es la esperada) sale como [SeguridadDispositivoException].
final class SeguridadDispositivoCanal implements SeguridadDispositivo {
  SeguridadDispositivoCanal({MethodChannel? canal}) : _canal = canal ?? const MethodChannel(nombre);

  /// Nombre del canal, el mismo en Kotlin y en Swift.
  static const String nombre = 'colportores/seguridad_dispositivo';

  final MethodChannel _canal;

  @override
  Future<bool> tieneBloqueoPantalla() async {
    final respuesta = await _invocar<bool>('bloqueoPantalla');
    return respuesta;
  }

  @override
  Future<NivelAlmacenSeguro> nivelAlmacenSeguro() async {
    final respuesta = await _invocar<String>('nivelAlmacen');
    return switch (respuesta) {
      'hardware' => NivelAlmacenSeguro.hardware,
      'software' => NivelAlmacenSeguro.software,
      _ => throw SeguridadDispositivoException(
        operacion: 'nivelAlmacen',
        causa: 'respuesta desconocida: $respuesta',
      ),
    };
  }

  Future<T> _invocar<T>(String metodo) async {
    final T? respuesta;
    try {
      respuesta = await _canal.invokeMethod<T>(metodo);
    } on Exception catch (e) {
      throw SeguridadDispositivoException(operacion: metodo, causa: e);
    }
    if (respuesta == null) {
      throw SeguridadDispositivoException(operacion: metodo, causa: 'respuesta vacía');
    }
    return respuesta;
  }
}
