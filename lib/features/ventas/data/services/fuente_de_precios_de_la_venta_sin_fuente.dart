import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/precios_de_la_venta.dart';
import '../../domain/repositories/fuente_de_precios_de_la_venta.dart';

/// Sin la base local abierta no se sabe con qué precios vender a un cliente (la fuente real es
/// `FuenteDePreciosDeLaVentaLocal`).
///
/// Devuelve la falla de lectura y nunca «campaña terminada»: afirmarlo bloquearía una venta que se
/// podría hacer.
final class FuenteDePreciosDeLaVentaSinFuente implements FuenteDePreciosDeLaVenta {
  FuenteDePreciosDeLaVentaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<Either<Failure, PreciosDeLaVenta>> leer({
    required String colportorId,
    required String espacioPersonaId,
  }) async {
    _log.warn(
      LogModulo.venta,
      'VENTA_PRECIOS_SIN_FUENTE',
      'la base local no está abierta: no se pueden leer los precios',
    );
    return const Left(FailurePreciosNoDisponibles());
  }
}
