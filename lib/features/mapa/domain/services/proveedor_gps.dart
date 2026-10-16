import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../value_objects/punto_capturado.dart';

/// Puerto hacia el GPS del teléfono (HU-UBI-001, "captura GPS").
///
/// El dominio declara qué necesita; el adaptador que envuelve el plugin vive en `data` y es el
/// único que lo conoce. HU-UBI-001 nombra `geolocator` en sus dependencias: el adaptador y los
/// permisos nativos (`AndroidManifest.xml`, `Info.plist`) llegan con la pantalla del alta, que es
/// la que pide el permiso. Hasta entonces el dominio se prueba con fakes.
abstract interface class ProveedorGps {
  /// La posición actual, con la precisión que reporta el SO.
  ///
  /// Sin GPS devuelve `Left(FailureGpsNoDisponible)` con el motivo (permiso denegado, ubicación
  /// apagada, sin señal): nunca lanza. No filtra `(0, 0)` ni la baja precisión: eso lo decide
  /// `CapturarPosicionGpsUseCase`.
  Future<Either<Failure, LecturaGps>> posicionActual();
}
