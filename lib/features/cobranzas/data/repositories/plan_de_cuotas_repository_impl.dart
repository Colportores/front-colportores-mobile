import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/cuota.dart';
import '../../domain/entities/pedido_de_plan.dart';
import '../../domain/repositories/plan_de_cuotas_repository.dart';
import '../datasources/cuotas_local_data_source_drift.dart';

/// [PlanDeCuotasRepository] sobre [CuotasLocalDataSourceDrift].
///
/// Traduce el rechazo de la persistencia a su `Failure` y cualquier otra excepción a
/// [FailurePlanNoGuardado] o [FailureCuotasNoGuardadas]; nunca deja escapar una. Al log van solo ids y
/// códigos: ni montos ni nada de la persona (convenciones §7.5).
final class PlanDeCuotasRepositoryImpl implements PlanDeCuotasRepository {
  PlanDeCuotasRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final CuotasLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, PlanDeCuotas>> crear(NuevoPlanDeCuotas plan) => _correr(
    'PLAN_CUOTAS_ALTA',
    {'venta_id': plan.ventaId},
    () => _local.crearPlan(plan),
    (causa) => FailurePlanNoGuardado(causa: causa),
  );

  @override
  Future<Either<Failure, PlanDeCuotas>> modificar(ModificacionDeCuotas cambios) => _correr(
    'PLAN_CUOTAS_CAMBIO',
    {'venta_id': cambios.ventaId},
    () => _local.modificarCuotas(cambios),
    (causa) => FailureCuotasNoGuardadas(causa: causa),
  );

  @override
  Future<Either<Failure, PlanDeCuotas?>> leer(String ventaId) => _correr(
    'PLAN_CUOTAS_LECTURA',
    {'venta_id': ventaId},
    () => _local.leerPlan(ventaId),
    (_) => const FailureCuotasNoDisponibles(),
  );

  @override
  Stream<PlanDeCuotas?> observar(String ventaId) =>
      _local.observarPlan(ventaId).handleError((Object error, StackTrace st) {
        _log.warn(LogModulo.db, 'PLAN_CUOTAS_STREAM_FAIL', 'no se pudieron leer las cuotas', {
          'tipo': error.runtimeType.toString(),
        });
        throw const FailureCuotasNoDisponibles();
      });

  Future<Either<Failure, T>> _correr<T>(
    String evento,
    Map<String, Object?> contexto,
    Future<T> Function() operacion,
    Failure Function(String causa) alFallar,
  ) async {
    try {
      return Right(await operacion());
    } on CuotasRechazadasException catch (e) {
      _log.info(LogModulo.db, '${evento}_RECHAZADO', 'plan de cuotas rechazado', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailurePlanDeCuotas(e.motivo));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló una operación del plan de cuotas',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(alFallar(tipo));
    }
  }
}
