import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/productos_de_la_entrega.dart';
import '../../domain/repositories/fuente_de_productos_de_la_entrega.dart';

/// Sin la base local abierta no hay de dónde leer los nombres de lo que se vendió (la fuente real es
/// `FuenteDeProductosDeLaEntregaLocal`).
///
/// Devuelve la falla de lectura y nunca un nombre inventado ni «no hay productos»: decirlo tapa un
/// error nuestro con un dato falso («Modo demo»: no se muestran datos simulados).
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
      'la base local no está abierta: no se puede leer el catálogo',
    );
    return const Left(FailureEntregaNoDisponible());
  }
}
