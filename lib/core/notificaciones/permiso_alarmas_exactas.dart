import 'dart:async';

import 'package:flutter/services.dart';

import 'permiso_notificaciones_sistema.dart';

/// Lo que el sistema dice de las alarmas exactas de la app (HU-NOT-002, «Aviso exacto»).
enum EstadoAlarmasExactas {
  /// La app puede programar avisos a la hora justa: el permiso «Alarmas y recordatorios» está
  /// prendido, o el Android es anterior al 12 y no lo pide.
  permitidas,

  /// Apagadas en los ajustes del teléfono: los avisos se programan inexactos y, con el teléfono en
  /// reposo, Android puede correrlos hasta una hora.
  apagadas,

  /// Este sistema no tiene el concepto (iOS): no hay nada que prender ni que avisar.
  noAplica,
}

/// El permiso «Alarmas y recordatorios» (`SCHEDULE_EXACT_ALARM`) de Android.
///
/// Puerto en Dart puro. La implementación de producción es [PermisoAlarmasExactasCanal], sobre el mismo
/// canal nativo de las notificaciones; la de los tests, un fake. Es la ÚNICA entrada para leer este
/// permiso (como [PermisoNotificacionesSistema]): `MotorDeAvisosPlugin` no llama al método equivalente
/// de su plugin. Toda falla de la plataforma sale como [PermisoAlarmasExactasException].
abstract interface class PermisoAlarmasExactas {
  /// Cómo están las alarmas exactas ahora. No le pide nada a la persona.
  Future<EstadoAlarmasExactas> leerEstado();

  /// Abre la pantalla «Alarmas y recordatorios» de la app en el teléfono. `false` si no pudo abrirla.
  Future<bool> abrirAjustes();
}

/// La plataforma no pudo responder por las alarmas exactas. [causa] va a logs, nunca al usuario.
final class PermisoAlarmasExactasException implements Exception {
  const PermisoAlarmasExactasException({required this.operacion, this.causa});

  /// `estado` o `abrirAjustes`.
  final String operacion;

  final Object? causa;

  @override
  String toString() => 'PermisoAlarmasExactasException($operacion)';
}

/// [PermisoAlarmasExactas] sobre el canal nativo `colportores/notificaciones` (el de
/// [PermisoNotificacionesCanal]).
///
/// Del otro lado: `MainActivity.kt` en Android y `AppDelegate.swift` en iOS. Los dos métodos:
/// `alarmasExactas` (→ `"permitidas"`, `"apagadas"` o `"noAplica"`) y `abrirAjustesAlarmas` (→ `bool`).
final class PermisoAlarmasExactasCanal implements PermisoAlarmasExactas {
  PermisoAlarmasExactasCanal({
    MethodChannel? canal,
    this.tiempoMaximo = const Duration(seconds: 10),
  }) : _canal = canal ?? const MethodChannel(PermisoNotificacionesCanal.nombre);

  /// Cuánto se espera la respuesta de la plataforma antes de dar por fallida la llamada.
  final Duration tiempoMaximo;

  final MethodChannel _canal;

  @override
  Future<EstadoAlarmasExactas> leerEstado() async {
    final respuesta = await _invocar<String>('alarmasExactas', operacion: 'estado');
    return switch (respuesta) {
      'permitidas' => EstadoAlarmasExactas.permitidas,
      'apagadas' => EstadoAlarmasExactas.apagadas,
      'noAplica' => EstadoAlarmasExactas.noAplica,
      _ => throw PermisoAlarmasExactasException(
        operacion: 'estado',
        causa: 'respuesta desconocida: $respuesta',
      ),
    };
  }

  @override
  Future<bool> abrirAjustes() => _invocar<bool>('abrirAjustesAlarmas', operacion: 'abrirAjustes');

  Future<T> _invocar<T>(String metodo, {required String operacion}) async {
    final T? respuesta;
    try {
      respuesta = await _canal.invokeMethod<T>(metodo).timeout(tiempoMaximo);
    } on Exception catch (e) {
      // `PlatformException`, `MissingPluginException` o `TimeoutException`.
      throw PermisoAlarmasExactasException(operacion: operacion, causa: e);
    }
    if (respuesta == null) {
      throw PermisoAlarmasExactasException(operacion: operacion, causa: 'respuesta vacía');
    }
    return respuesta;
  }
}
