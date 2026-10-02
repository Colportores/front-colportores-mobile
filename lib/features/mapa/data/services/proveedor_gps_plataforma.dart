import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/services/activador_gps.dart';
import '../../domain/services/proveedor_gps.dart';
import '../../domain/value_objects/punto_capturado.dart';
import 'plataforma_gps.dart';

/// Adaptador de [ProveedorGps] y [ActivadorGps] sobre [PlataformaGps] (HU-UBI-001).
///
/// Nunca lanza: cualquier falla de la plataforma es `Left(FailureGpsNoDisponible)` con el motivo
/// que le sirve a la pantalla («Activar GPS»). Esta es la pantalla que pide el permiso, la primera
/// vez que se abre el alta. Loguea en `[MAP]` sin coordenadas.
final class ProveedorGpsPlataforma implements ProveedorGps, ActivadorGps {
  ProveedorGpsPlataforma(
    this._plataforma, {
    this.limite = const Duration(seconds: 15),
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final PlataformaGps _plataforma;

  /// Cuánto se espera una posición antes de tratarla como sin señal.
  final Duration limite;

  final AppLogger _log;

  @override
  Future<Either<Failure, LecturaGps>> posicionActual() async {
    try {
      if (!await _plataforma.servicioActivo()) {
        return const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado));
      }
      var permiso = await _plataforma.permiso();
      if (permiso == PermisoUbicacion.denegado) permiso = await _plataforma.pedirPermiso();
      if (permiso != PermisoUbicacion.concedido) {
        return const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado));
      }
      return Right(await _plataforma.leer(limite: limite));
    } on Object catch (e) {
      _log.warn(LogModulo.map, 'GPS_LECTURA_FAIL', 'no se pudo leer el GPS', {
        'causa': e.runtimeType.toString(),
      });
      return const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal));
    }
  }

  @override
  Future<void> activar(MotivoSinGps motivo) async {
    try {
      switch (motivo) {
        case MotivoSinGps.servicioApagado:
          await _plataforma.abrirAjustesUbicacion();
        case MotivoSinGps.permisoDenegado:
          var permiso = await _plataforma.permiso();
          if (permiso == PermisoUbicacion.denegado) permiso = await _plataforma.pedirPermiso();
          if (permiso == PermisoUbicacion.denegadoParaSiempre) {
            await _plataforma.abrirAjustesApp();
          }
        case MotivoSinGps.sinSenal:
          break;
      }
    } on Object catch (e) {
      _log.warn(LogModulo.map, 'GPS_ACTIVAR_FAIL', 'no se pudo activar el GPS', {
        'causa': e.runtimeType.toString(),
      });
    }
  }
}
