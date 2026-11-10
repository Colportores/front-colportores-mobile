import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/productos_de_la_entrega.dart';
import '../../domain/repositories/fuente_de_productos_de_la_entrega.dart';

/// Sin la réplica local del catálogo (HU-CAT-007, #180) y su adaptador (front-colportores-mobile#274)
/// no hay de dónde leer los nombres de lo que se vendió.
///
/// Devuelve la falla de lectura y nunca un nombre inventado ni «no hay productos»: decirlo tapa un
/// error nuestro con un dato falso («Modo demo»: no se muestran datos simulados). **No es la regla de
/// la HU**: se reemplaza cuando llegue el adaptador. La app no sale a producción con esta clase.
final class FuenteDeProductosDeLaEntregaSinFuente implements FuenteDeProductosDeLaEntrega {
  FuenteDeProductosDeLaEntregaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<Either<Failure, ProductosDeLaEntrega>> leer({
    required Set<String> productoIds,
    required Set<String> comboIds,
  }) async {
    _log.warn(
      LogModulo.venta,
      'ENTREGA_PRODUCTOS_SIN_FUENTE',
      'no hay catálogo en el teléfono (falta el adaptador de #274)',
    );
    return const Left(FailureEntregaNoDisponible());
  }
}
