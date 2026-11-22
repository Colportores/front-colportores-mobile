import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/productos_de_la_entrega.dart';

/// De dónde salen los nombres de lo que se vendió, para mostrar qué se entrega («Salud y Hogar × 1»).
/// Lo implementa la réplica local del catálogo (HU-CAT-007, front-colportores-mobile#180) cuando
/// llegue su adaptador (#274); hasta entonces, `FuenteDeProductosDeLaEntregaSinFuente`.
abstract interface class FuenteDeProductosDeLaEntrega {
  /// Los nombres de [productoIds] y, de cada combo de [comboIds], qué productos lleva siempre (su
  /// base). Incluye los productos y combos dados de baja: la venta ya se hizo. `Left` si no se puede
  /// leer (nunca un nombre inventado).
  Future<Either<Failure, ProductosDeLaEntrega>> leer({
    required Set<String> productoIds,
    required Set<String> comboIds,
  });
}
