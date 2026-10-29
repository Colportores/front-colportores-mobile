import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/services/recordatorios.dart';
import '../entities/cuota.dart';
import '../entities/pedido_de_plan.dart';
import '../repositories/plan_de_cuotas_repository.dart';
import '../services/reparto_de_cuotas.dart';

/// Parámetros de [ArmarPlanDeCuotasUseCase].
final class ArmarPlanParams extends Equatable {
  const ArmarPlanParams({
    required this.ventaId,
    required this.colportorId,
    required this.frecuencia,
    required this.primeraCuota,
    required this.montosCentavos,
    required this.idsDeLasCitas,
    this.direccion = '',
  });

  final String ventaId;
  final String colportorId;
  final FrecuenciaDeCuotas frecuencia;

  /// El día de la primera cuota (solo cuenta el día); hoy o más adelante.
  final DateTime primeraCuota;

  /// El monto de cada cuota, en el orden del plan: su cantidad es la cantidad de cuotas.
  final List<int> montosCentavos;

  /// El `agenda.id` de cada cuota, uno por cuota: los genera quien abre la pantalla y se repiten en
  /// los reintentos, así un doble toque o un reintento no agenda dos veces.
  final List<String> idsDeLasCitas;

  /// La dirección de la casa, para el recordatorio de cada cobranza («Cobranza en … a las 10:00»);
  /// puede ir vacía.
  final String direccion;

  @override
  List<Object?> get props => [
    ventaId,
    colportorId,
    frecuencia,
    primeraCuota,
    montosCentavos,
    idsDeLasCitas,
    direccion,
  ];
}

/// El plan que quedó armado y cuántos recordatorios no van a sonar (apagados, sin permiso o sin hora).
final class PlanArmado extends Equatable {
  const PlanArmado({required this.plan, required this.sinRecordatorio});

  final PlanDeCuotas plan;

  /// Cuántas de las cobranzas agendadas quedaron sin recordatorio. Las citas se guardaron igual.
  final int sinRecordatorio;

  @override
  List<Object?> get props => [plan, sinRecordatorio];
}

/// HU-COB-004: arma el plan de cuotas de una venta con saldo (vista 30 A).
///
/// 1. Valida lo que cargó la colportora y **no guarda nada** si algo está mal: de 2 a 12 cuotas, un
///    monto y un id de cita por cuota, y la primera cuota hoy o más adelante.
/// 2. Reparte las fechas (semanal: cada 7 días; mensual: el mismo día de cada mes).
/// 3. Agenda una cobranza por cuota por [PlanDeCuotasRepository.crear], que escribe todo o nada, las
///    encola para el sync y recalcula el color de la casa. Ninguna cuota supera el saldo y entre
///    todas no lo superan (la base lo vuelve a medir, dentro de la transacción).
/// 4. Programa el recordatorio de cada cobranza que no haya pasado. Programar nunca hace fallar el
///    plan: lo que no se pudo se cuenta en [PlanArmado.sinRecordatorio].
///
/// Todo es local: sin conexión se arma igual.
final class ArmarPlanDeCuotasUseCase implements UseCase<PlanArmado, ArmarPlanParams> {
  ArmarPlanDeCuotasUseCase(this._repository, this._recordatorios, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PlanDeCuotasRepository _repository;
  final Recordatorios _recordatorios;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, PlanArmado>> call(ArmarPlanParams params) async {
    final cantidad = params.montosCentavos.length;
    if (params.ventaId.trim().isEmpty ||
        params.colportorId.trim().isEmpty ||
        params.idsDeLasCitas.length != cantidad ||
        params.idsDeLasCitas.any((id) => id.trim().isEmpty)) {
      return const Left(FailurePlanNoGuardado(causa: 'faltan_ids'));
    }
    if (cantidad < RepartoDeCuotas.minimo || cantidad > RepartoDeCuotas.maximo) {
      return const Left(FailurePlanDeCuotas(MotivoPlanDeCuotas.cantidad));
    }
    if (params.montosCentavos.any((m) => m <= 0)) {
      return const Left(FailurePlanDeCuotas(MotivoPlanDeCuotas.montos));
    }
    final ahora = _ahora();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final primera = DateTime(
      params.primeraCuota.year,
      params.primeraCuota.month,
      params.primeraCuota.day,
    );
    if (primera.isBefore(hoy)) {
      return const Left(FailurePlanDeCuotas(MotivoPlanDeCuotas.fechaPasada));
    }

    final fechas = RepartoDeCuotas.fechas(
      primera: primera,
      cantidad: cantidad,
      frecuencia: params.frecuencia,
    );
    final guardado = await _repository.crear(
      NuevoPlanDeCuotas(
        ventaId: params.ventaId.trim(),
        colportorId: params.colportorId.trim(),
        ahora: ahora,
        cuotas: [
          for (var i = 0; i < cantidad; i++)
            NuevaCuota(
              agendaId: params.idsDeLasCitas[i].trim(),
              fecha: fechas[i],
              montoCentavos: params.montosCentavos[i],
            ),
        ],
      ),
    );
    Failure? falla;
    PlanDeCuotas? plan;
    guardado.fold((f) => falla = f, (p) => plan = p);
    final armado = plan;
    if (armado == null) return Left(falla ?? const FailurePlanNoGuardado());

    var sin = 0;
    for (var i = 0; i < cantidad; i++) {
      final cuando = fechas[i];
      final resultado = cuando.isBefore(ahora)
          ? ResultadoRecordatorio.yaPaso
          : await _programar(params.idsDeLasCitas[i].trim(), cuando, params.direccion);
      if (resultado != ResultadoRecordatorio.programado) sin++;
    }
    return Right(PlanArmado(plan: armado, sinRecordatorio: sin));
  }

  Future<ResultadoRecordatorio> _programar(
    String agendaId,
    DateTime cuando,
    String direccion,
  ) async {
    try {
      return await _recordatorios.programar(
        RecordatorioDeVisita(
          agendaId: agendaId,
          tipo: TipoAgenda.cobranza,
          direccion: direccion,
          fechaProgramada: cuando,
        ),
      );
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.agenda,
        'PLAN_CUOTAS_RECORDATORIO',
        'no se pudo programar el recordatorio de una cuota',
        {'agenda_id': agendaId, 'error': e.runtimeType.toString()},
      );
      return ResultadoRecordatorio.noSePudo;
    }
  }
}
