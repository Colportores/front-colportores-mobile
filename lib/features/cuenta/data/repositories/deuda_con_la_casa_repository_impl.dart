import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/deuda_con_la_casa.dart';
import '../../domain/repositories/deuda_con_la_casa_repository.dart';
import '../../domain/services/calculador_de_la_deuda.dart';
import '../datasources/deuda_con_la_casa_local_data_source.dart';

/// [DeudaConLaCasaRepository] sobre lo que baja con la sincronización: cuenta la deuda en el teléfono
/// con [CalculadorDeLaDeuda] y la fecha con la hora de la última bajada.
///
/// Una base que no se puede leer es [FailureDeudaNoDisponible], nunca un «$ 0». Al log va solo el tipo
/// de la falla (convenciones §7.5): ni montos ni ids.
final class DeudaConLaCasaRepositoryImpl implements DeudaConLaCasaRepository {
  DeudaConLaCasaRepositoryImpl(this._local, {required this._ahora, AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final DeudaConLaCasaLocalDataSource _local;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Stream<void> get cambios => _local.cambios;

  @override
  Future<Either<Failure, LecturaDeLaDeuda?>> leer(String colportorId) async {
    try {
      final bajada = await _local.leer(colportorId);
      if (bajada == null) return const Right(null);
      return Right(
        LecturaDeLaDeuda(
          deuda: CalculadorDeLaDeuda.calcular(bajada.insumos, ahora: _ahora()),
          leidaEn: bajada.ultimaBajada.toUtc(),
        ),
      );
    } on Object catch (e) {
      _log.warn(LogModulo.db, 'DEUDA_CASA_LEER_FAIL', 'no se pudo leer la deuda', {
        'tipo': e.runtimeType.toString(),
      });
      return const Left(FailureDeudaNoDisponible());
    }
  }
}

/// Sin DB abierta no hay de dónde leer la deuda: como si no se pudiera leer.
final class DeudaConLaCasaSinBase implements DeudaConLaCasaRepository {
  const DeudaConLaCasaSinBase();

  @override
  Stream<void> get cambios => const Stream.empty();

  @override
  Future<Either<Failure, LecturaDeLaDeuda?>> leer(String colportorId) async =>
      const Left(FailureDeudaNoDisponible());
}
