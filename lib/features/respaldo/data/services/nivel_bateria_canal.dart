import 'package:flutter/services.dart';

import '../../domain/services/nivel_bateria.dart';

/// [NivelBateria] sobre el canal nativo `colportores/bateria`.
///
/// Del otro lado: `MainActivity.kt` (Android, `BatteryManager`) y `AppDelegate.swift` (iOS,
/// `UIDevice.batteryLevel`). Expone `nivel` (→ `int` de 0 a 100, o `null` si el sistema no lo
/// informa). Es un canal chico y propio, como los demás de la app: no hay un plugin más que
/// mantener para una sola pregunta.
final class NivelBateriaCanal implements NivelBateria {
  NivelBateriaCanal({MethodChannel? canal, this.tiempoMaximo = const Duration(seconds: 5)})
    : _canal = canal ?? const MethodChannel(nombre);

  /// Nombre del canal, el mismo en Kotlin y en Swift.
  static const String nombre = 'colportores/bateria';

  final MethodChannel _canal;
  final Duration tiempoMaximo;

  @override
  Future<int?> porcentaje() async {
    try {
      final nivel = await _canal.invokeMethod<int>('nivel').timeout(tiempoMaximo);
      if (nivel == null || nivel < 0 || nivel > 100) return null;
      return nivel;
    } on Object {
      // Sin canal (escritorio, tests) o con un fallo: no saber el nivel no frena el respaldo.
      return null;
    }
  }
}

/// Sin dato de batería: nunca frena el respaldo. Es lo que corre en los tests y en la demo.
final class NivelBateriaDesconocido implements NivelBateria {
  const NivelBateriaDesconocido();

  @override
  Future<int?> porcentaje() async => null;
}
