import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/catalogo_local.dart';
import '../../domain/entities/ciudad_consultable.dart';
import '../../domain/repositories/consulta_de_precios_repository.dart';
import '../../domain/repositories/fecha_de_los_precios.dart';
import '../../domain/repositories/fuente_de_ciudades_para_precios.dart';

// Puertos de la consulta de precios (HU-CAT-006) cuya fuente real todavía no existe. **Ninguno es la
// regla de la HU**: se reemplazan cuando llegue lo que les falta.

/// Sin la réplica local del catálogo de ventas (`producto`, `coleccion`, `producto_coleccion`,
/// `precio_por_ciudad` y `precio_general` llegan con el pull de catálogos, front-colportores-mobile#180;
/// además, `producto.codigo_editor` y `parametro_global`, backend-supabase 0070): no hay qué leer.
///
/// **No sabe, así que no afirma que no hay precios**: emite un error (26·10, «No pudimos leer los
/// precios guardados en tu teléfono.», con «Reintentar»). La app no sale a producción con esta clase.
final class ConsultaDePreciosSinFuente implements ConsultaDePreciosRepository {
  ConsultaDePreciosSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Stream<CatalogoLocal> observar(String campaniaCiudadId) {
    _log.warn(
      LogModulo.stock,
      'PRECIOS_SIN_FUENTE',
      'no hay catálogo de ventas en el teléfono (falta la réplica local del catálogo)',
    );
    return Stream.error(const FailurePreciosNoDisponibles());
  }
}

/// Sin la réplica local de `ciudad`, `campania` y `campania_colportor` (adaptador real:
/// front-colportores-mobile#274): no se sabe en qué ciudades de qué campañas puede consultar.
///
/// Devuelve la falla de lectura y nunca «no tenés campañas»: afirmarlo la mandaría a reclamar una
/// inscripción que quizá tiene. La app no sale a producción con esta clase.
final class FuenteDeCiudadesParaPreciosSinFuente implements FuenteDeCiudadesParaPrecios {
  FuenteDeCiudadesParaPreciosSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<Either<Failure, ContextoDeCiudades>> leer(String colportorId) async {
    _log.warn(
      LogModulo.stock,
      'PRECIOS_CIUDADES_SIN_FUENTE',
      'no hay ciudades ni campañas en el teléfono (falta la réplica local de #274)',
    );
    return const Left(FailurePreciosNoDisponibles());
  }
}

/// Mientras no hay de dónde leer cuándo bajaron los precios: no se sabe, y la pantalla no inventa una
/// fecha.
final class FechaDeLosPreciosDesconocida implements FechaDeLosPrecios {
  const FechaDeLosPreciosDesconocida();

  @override
  Future<DateTime?> ultimaBajada() async => null;
}

/// Mientras la réplica de `parametro_global` no llegue al teléfono rigen los 15 días de siempre (el
/// valor sembrado por backend-supabase 0070).
final class DiasDeAntiguedadPorDefecto implements DiasDeAntiguedadDePrecios {
  const DiasDeAntiguedadPorDefecto(this._dias);

  final int _dias;

  @override
  Future<int> dias() async => _dias;
}
