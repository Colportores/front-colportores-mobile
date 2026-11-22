import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/agenda.dart';
import '../repositories/agenda_repository.dart';
import '../services/recordatorios.dart';

/// Parámetros de [CancelarAgendaUseCase].
final class CancelarAgendaParams extends Equatable {
  const CancelarAgendaParams({required this.agendaId});

  /// `agenda.id` de la agenda que se cancela.
  final String agendaId;

  @override
  List<Object?> get props => [agendaId];
}

/// Lo que devuelve [CancelarAgendaUseCase]: la agenda como quedó y si el recordatorio se pudo sacar.
final class ResultadoCancelarAgenda extends Equatable {
  const ResultadoCancelarAgenda({required this.agenda, required this.recordatorioCancelado});

  /// La agenda en estado `CANCELADA`.
  final Agenda agenda;

  /// `false` si el teléfono no pudo cancelar el aviso: la agenda igual quedó cancelada, pero el
  /// recordatorio podría sonar. Quien lo muestra tiene que decírselo a la colportora.
  final bool recordatorioCancelado;

  @override
  List<Object?> get props => [agenda, recordatorioCancelado];
}

/// HU-VIS-004 — Cancelar una agenda `PROGRAMADA`.
///
/// 1. Valida el id. En blanco: `Left(FailureValidacion)` con el campo `agenda`, sin tocar la DB.
/// 2. Pasa la agenda a `CANCELADA` (no se borra) en **una transacción local** del repositorio: la
///    fila, su job de sync y el color de la casa en `house_status` (si era la única entrevista
///    programada, la casa vuelve al color que le corresponde sin ella). Una agenda cumplida, no
///    cumplida o inexistente es un `Left(FailureValidacion)` con el campo `agenda`.
/// 3. Saca el recordatorio local (HU-NOT-002). Va **después** de la transacción: si cancelar falla,
///    el aviso sigue (la agenda sigue programada). Si el teléfono no puede sacarlo, la agenda queda
///    cancelada igual y [ResultadoCancelarAgenda.recordatorioCancelado] lo dice.
///
/// Cancelar una agenda ya cancelada no escribe nada y devuelve la agenda (un doble toque no es un
/// error), pero **vuelve a pedir** sacar el recordatorio: así el reintento de una cancelación que
/// dejó el aviso vivo lo arregla. Todo es local: sin conexión se completa igual.
final class CancelarAgendaUseCase
    implements UseCase<ResultadoCancelarAgenda, CancelarAgendaParams> {
  CancelarAgendaUseCase(this._repository, this._recordatorios, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AgendaRepository _repository;
  final Recordatorios _recordatorios;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, ResultadoCancelarAgenda>> call(CancelarAgendaParams params) async {
    final agendaId = params.agendaId.trim();
    if (agendaId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'agenda': 'Falta el identificador de la agenda'}),
      );
    }

    final cancelada = await _repository.cancelar(agendaId, ahora: _ahora());
    return cancelada.fold(
      (falla) async => Left<Failure, ResultadoCancelarAgenda>(falla),
      (agenda) async => Right(
        ResultadoCancelarAgenda(
          agenda: agenda,
          recordatorioCancelado: await _sacarRecordatorio(agendaId),
        ),
      ),
    );
  }

  /// `Recordatorios.cancelar` no lanza, pero una falla del plugin nunca debe deshacer una agenda ya
  /// cancelada: cualquier excepción cuenta como «no se pudo».
  Future<bool> _sacarRecordatorio(String agendaId) async {
    try {
      return await _recordatorios.cancelar(agendaId);
    } on Object {
      return false;
    }
  }
}
