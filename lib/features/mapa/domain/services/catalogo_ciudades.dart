import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';

/// Puerto: el catálogo de ciudades (Admin). No hay tabla `ciudad` en la DB local todavía; hasta
/// entonces no hay implementación de producción (HU-UBI-005, reactivar con la ciudad borrada).
abstract interface class CatalogoCiudades {
  /// `true` si [ciudadId] sigue en el catálogo.
  Future<Either<Failure, bool>> existe(String ciudadId);
}
