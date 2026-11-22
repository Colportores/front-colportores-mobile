import 'dart:async';

import 'package:flutter/services.dart';

/// Lo que el sistema dice de las notificaciones de la app (HU-NOT-001, vista 24).
enum EstadoSistemaNotificaciones {
  /// La app puede mostrar notificaciones.
  activadas,

  /// El sistema todavía no le preguntó a la persona (iOS lo distingue; Android no).
  sinPreguntar,

  /// Apagadas: la persona dijo que no o las apagó en los ajustes del teléfono. En Android, sin la
  /// marca propia de «ya se le preguntó» (`PermisoNotificacionesRepository`), esto también es lo que
  /// se ve antes de la primera pregunta.
  apagadas,
}

/// El permiso de notificaciones del sistema operativo (Android 13 o más: `POST_NOTIFICATIONS`; iOS:
/// `UNUserNotificationCenter`).
///
/// Puerto en Dart puro. La implementación de producción es [PermisoNotificacionesCanal], sobre un
/// canal nativo chico y propio (como `SeguridadDispositivoCanal`); la de los tests, un fake. Pedir el
/// permiso no necesita Firebase: el registro del teléfono para las push (HU-NOT-003) llega en el S11.
///
/// Es la ÚNICA entrada para pedir y leer este permiso (decisión del orquestador, 26/10, P1): los
/// recordatorios locales (`flutter_local_notifications`) y las push del S11 lo usan y no llaman a
/// los métodos de permiso de su plugin, para que nunca haya dos caminos para lo mismo.
/// Toda falla de la plataforma sale como [PermisoNotificacionesException].
abstract interface class PermisoNotificacionesSistema {
  /// Cómo están las notificaciones ahora. No le pide nada a la persona.
  Future<EstadoSistemaNotificaciones> leerEstado();

  /// Muestra el diálogo del sistema (si el sistema todavía lo permite) y devuelve si quedaron
  /// activadas. Sin diálogo posible (ya se negó, o Android anterior al 13) devuelve el estado de
  /// ahora, sin esperar.
  Future<bool> pedir();

  /// Abre los ajustes de notificaciones de la app en el teléfono. `false` si no pudo abrirlos.
  Future<bool> abrirAjustes();
}

/// La plataforma no pudo responder por las notificaciones. [causa] va a logs, nunca al usuario.
final class PermisoNotificacionesException implements Exception {
  const PermisoNotificacionesException({required this.operacion, this.causa});

  /// `estado`, `pedir` o `abrirAjustes`.
  final String operacion;

  final Object? causa;

  @override
  String toString() => 'PermisoNotificacionesException($operacion)';
}

/// [PermisoNotificacionesSistema] sobre el canal nativo `colportores/notificaciones`.
///
/// Del otro lado: `MainActivity.kt` en Android y `AppDelegate.swift` en iOS. Los tres métodos:
/// `estado` (→ `"activadas"`, `"sinPreguntar"` o `"apagadas"`), `pedir` (→ `bool`, espera la
/// respuesta de la persona al diálogo del sistema) y `abrirAjustes` (→ `bool`).
final class PermisoNotificacionesCanal implements PermisoNotificacionesSistema {
  PermisoNotificacionesCanal({
    MethodChannel? canal,
    this.tiempoMaximo = const Duration(seconds: 10),
  }) : _canal = canal ?? const MethodChannel(nombre);

  /// Nombre del canal, el mismo en Kotlin y en Swift.
  static const String nombre = 'colportores/notificaciones';

  /// Cuánto se espera la respuesta de `estado` y `abrirAjustes`. `pedir` no tiene tope: espera lo
  /// que tarde la persona en contestar el diálogo.
  final Duration tiempoMaximo;

  final MethodChannel _canal;

  @override
  Future<EstadoSistemaNotificaciones> leerEstado() async {
    final respuesta = await _invocar<String>('estado', tope: tiempoMaximo);
    return switch (respuesta) {
      'activadas' => EstadoSistemaNotificaciones.activadas,
      'sinPreguntar' => EstadoSistemaNotificaciones.sinPreguntar,
      'apagadas' => EstadoSistemaNotificaciones.apagadas,
      _ => throw PermisoNotificacionesException(
        operacion: 'estado',
        causa: 'respuesta desconocida: $respuesta',
      ),
    };
  }

  @override
  Future<bool> pedir() => _invocar<bool>('pedir');

  @override
  Future<bool> abrirAjustes() => _invocar<bool>('abrirAjustes', tope: tiempoMaximo);

  Future<T> _invocar<T>(String metodo, {Duration? tope}) async {
    final T? respuesta;
    try {
      final llamada = _canal.invokeMethod<T>(metodo);
      respuesta = await (tope == null ? llamada : llamada.timeout(tope));
    } on Exception catch (e) {
      // `PlatformException`, `MissingPluginException` o `TimeoutException`.
      throw PermisoNotificacionesException(operacion: metodo, causa: e);
    }
    if (respuesta == null) {
      throw PermisoNotificacionesException(operacion: metodo, causa: 'respuesta vacía');
    }
    return respuesta;
  }
}
