import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/cuota.dart';
import '../entities/pedido_de_plan.dart';
import '../repositories/plan_de_cuotas_repository.dart';

/// Parámetros de [ModificarCuotasUseCase].
final class ModificarCuotasParams extends Equatable {
  const ModificarCuotasParams({required this.ventaId, required this.montosPorCuota});

  final String ventaId;

  /// `agenda.id` de cada cuota abierta → su monto nuevo, en centavos.
  final Map<String, int> montosPorCuota;

  @override
  List<Object?> get props => [ventaId, montosPorCuota];
}

/// HU-COB-004: modifica las cuotas que no están cerradas (30A-09). Las cubiertas no se tocan; los
/// montos que no entran (cero, más de lo que falta repartir, menos de lo ya cobrado de una cuota) se
/// rechazan sin guardar nada. Al guardar se reprograman las cobranzas de esas cuotas: cada cita se
/// actualiza y sube por el motor.
final class ModificarCuotasUseCase implements UseCase<PlanDeCuotas, ModificarCuotasParams> {
  ModificarCuotasUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PlanDeCuotasRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, PlanDeCuotas>> call(ModificarCuotasParams params) async {
    if (params.ventaId.trim().isEmpty || params.montosPorCuota.isEmpty) {
      return const Left(FailureCuotasNoGuardadas(causa: 'faltan_datos'));
    }
    return _repository.modificar(
      ModificacionDeCuotas(
        ventaId: params.ventaId.trim(),
        ahora: _ahora(),
        cambios: [
          for (final e in params.montosPorCuota.entries)
            CambioDeCuota(agendaId: e.key, montoCentavos: e.value),
        ],
      ),
    );
  }
}
