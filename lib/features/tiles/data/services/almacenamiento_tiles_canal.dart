import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/puertos_descarga.dart';

/// El espacio libre del volumen de los paquetes y la exclusión de la copia de seguridad, sobre el
/// canal nativo `colportores/almacenamiento_tiles` (decisión d5 de #189: no hay un plugin que lo
/// dé sin sumar otros permisos).
///
/// Del otro lado: `MainActivity.kt` (`StatFs(ruta).availableBytes`) y `AppDelegate.swift`
/// (`volumeAvailableCapacityForImportantUsage`, lo que iOS le puede dar a la app incluso liberando
/// lo purgable). Los dos métodos reciben `{ruta}`:
/// - `bytesLibres` → `int`.
/// - `excluirDeBackup` → `bool`. En iOS marca la carpeta con `isExcludedFromBackup` (los mapas se
///   vuelven a bajar: no tienen por qué ir a iCloud); en Android no hace falta, la app ya tiene
///   `allowBackup="false"`.
///
/// Si la plataforma no contesta o falla, [bytesLibres] no frena la descarga: devuelve [sinMedida]
/// y queda el log. Si el disco se llena a mitad, la escritura lo avisa (`ErrorEspacioTiles`).
final class AlmacenamientoTilesCanal implements MedidorEspacioDisco {
  AlmacenamientoTilesCanal(
    this._directorio, {
    MethodChannel? canal,
    this.tiempoMaximo = tiempoMaximoPorDefecto,
    AppLogger? logger,
  }) : _canal = canal ?? const MethodChannel(nombre),
       _logger = logger ?? AppLogger.instance;

  /// Nombre del canal, el mismo en Kotlin y en Swift.
  static const String nombre = 'colportores/almacenamiento_tiles';

  static const Duration tiempoMaximoPorDefecto = Duration(seconds: 10);

  /// Lo que se informa cuando no se pudo medir: más que cualquier paquete.
  static const int sinMedida = 1 << 62;

  final Directory _directorio;
  final MethodChannel _canal;
  final Duration tiempoMaximo;
  final AppLogger _logger;

  @override
  Future<int> bytesLibres() async {
    try {
      final libres = await _canal
          .invokeMethod<int>('bytesLibres', {'ruta': _directorio.path})
          .timeout(tiempoMaximo);
      if (libres == null || libres < 0) throw const FormatException('respuesta inválida');
      return libres;
    } on Object catch (e) {
      _logger.warn(LogModulo.map, 'espacio', 'no se pudo medir el espacio libre', {
        'error': e.runtimeType.toString(),
      });
      return sinMedida;
    }
  }

  /// Saca la carpeta de los paquetes de la copia de seguridad. Si no se puede, queda en el log: no
  /// es motivo para no usar los mapas.
  Future<void> excluirDeBackup() async {
    try {
      await _canal
          .invokeMethod<bool>('excluirDeBackup', {'ruta': _directorio.path})
          .timeout(tiempoMaximo);
    } on Object catch (e) {
      _logger.warn(LogModulo.map, 'backup', 'no se pudo excluir la carpeta del respaldo', {
        'error': e.runtimeType.toString(),
      });
    }
  }
}
