import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/precios_de_la_venta.dart';

/// De dónde sale la ciudad (y la campaña en curso) de la casa de un cliente, para saber con qué
/// precios vender. Lo implementa `FuenteDePreciosDeLaVentaLocal`, sobre la casa del cliente y las
/// réplicas locales de `ciudad`, `campania`, `campania_ciudad` y `campania_colportor`; sin la base
/// abierta, `FuenteDePreciosDeLaVentaSinFuente`.
abstract interface class FuenteDePreciosDeLaVenta {
  /// La ciudad de la casa del vínculo [espacioPersonaId], en la campaña en curso de [colportorId].
  /// `Left` si no se puede leer (nunca un «no hay campaña» inventado: eso dejaría a la colportora sin
  /// vender por un error nuestro).
  Future<Either<Failure, PreciosDeLaVenta>> leer({
    required String colportorId,
    required String espacioPersonaId,
  });
}
