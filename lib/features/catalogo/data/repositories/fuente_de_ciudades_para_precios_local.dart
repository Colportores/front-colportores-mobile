import 'package:dartz/dartz.dart';

import '../../../../core/database/dia_de_calendario.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/ciudad_consultable.dart';
import '../../domain/repositories/fuente_de_ciudades_para_precios.dart';
import '../datasources/ciudades_para_precios_local_data_source.dart';

/// [FuenteDeCiudadesParaPrecios] sobre las réplicas locales del pull de catálogos (`campania_colportor`,
/// `campania`, `campania_ciudad`, `ciudad` y `zona`): lee solo del teléfono, sin red (HU-CAT-006,
/// front-colportores-mobile#421).
///
/// «Hoy», que decide qué campañas ya terminaron, es el día de Montevideo ([diaDeCalendario]), como
/// `hoy_montevideo()` del servidor.
///
/// **Qué es «no sé».** Una `Left` ([FailurePreciosNoDisponibles], el aviso 26·10) es que no se pudo
/// leer: la lectura falló, o el teléfono todavía no bajó el catálogo (ningún pull terminó, o falta una
/// campaña o una ciudad a la que apunta una fila). Un [ContextoDeCiudades] sin ciudades es solo para
/// cuando se leyó y de verdad no hay: afirmarlo sin saberlo mandaría a la colportora a reclamar una
/// inscripción que quizá tiene.
final class FuenteDeCiudadesParaPreciosLocal implements FuenteDeCiudadesParaPrecios {
  FuenteDeCiudadesParaPreciosLocal(this._datos, {DateTime Function()? ahora, AppLogger? logger})
    : _ahora = ahora ?? DateTime.now,
      _log = logger ?? AppLogger.instance;

  final CiudadesParaPreciosLocalDataSource _datos;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Future<Either<Failure, ContextoDeCiudades>> leer(String colportorId) async {
    try {
      final contexto = await _datos.leer(colportorId, hoy: diaDeCalendario(_ahora()));
      if (contexto == null) {
        _log.warn(
          LogModulo.stock,
          'PRECIOS_CIUDADES_SIN_BAJAR',
          'el teléfono todavía no bajó las campañas y ciudades de la colportora',
        );
        return const Left(FailurePreciosNoDisponibles());
      }
      return Right(contexto);
    } on Object catch (e) {
      _log.warn(LogModulo.stock, 'PRECIOS_CIUDADES_FAIL', 'no se pudieron leer las ciudades', {
        'causa': e.runtimeType.toString(),
      });
      return const Left(FailurePreciosNoDisponibles());
    }
  }
}
