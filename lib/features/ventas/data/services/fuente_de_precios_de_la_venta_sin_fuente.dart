import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/precios_de_la_venta.dart';
import '../../domain/repositories/fuente_de_precios_de_la_venta.dart';

/// Sin la réplica local de `ciudad`, `campania` y `campania_ciudad` (adaptador real:
/// front-colportores-mobile#274) no se sabe con qué precios vender a un cliente.
///
/// Devuelve la falla de lectura y nunca «campaña terminada»: afirmarlo bloquearía una venta que se
/// podría hacer. **No es la regla de la HU**: se reemplaza cuando llegue #274. La app no sale a
/// producción con esta clase.
final class FuenteDePreciosDeLaVentaSinFuente implements FuenteDePreciosDeLaVenta {
  FuenteDePreciosDeLaVentaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<Either<Failure, PreciosDeLaVenta>> leer(String espacioPersonaId) async {
    _log.warn(
      LogModulo.venta,
      'VENTA_PRECIOS_SIN_FUENTE',
      'no hay ciudades ni campañas en el teléfono (falta la réplica local de #274)',
    );
    return const Left(FailurePreciosNoDisponibles());
  }
}
