import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/precios_de_la_venta.dart';

/// De dónde sale la ciudad (y la campaña en curso) de la casa de un cliente, para saber con qué
/// precios vender. Lo implementa la réplica local de `ciudad`, `campania` y `campania_ciudad`
/// (front-colportores-mobile#274); hasta entonces, `FuenteDePreciosDeLaVentaSinFuente`.
abstract interface class FuenteDePreciosDeLaVenta {
  /// La ciudad de la casa del vínculo [espacioPersonaId]. `Left` si no se puede leer (nunca un «no
  /// hay campaña» inventado: eso dejaría a la colportora sin vender por un error nuestro).
  Future<Either<Failure, PreciosDeLaVenta>> leer(String espacioPersonaId);
}
