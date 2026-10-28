import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../agenda/domain/entities/recordatorio_de_visita.dart';
import '../../../agenda/domain/services/recordatorios.dart';
import '../entities/entrega_diferida.dart';
import '../repositories/entrega_repository.dart';
import 'diferir_entrega_use_case.dart';

/// Parámetros de [CumplirEntregaUseCase].
final class CumplirEntregaParams extends Equatable {
  const CumplirEntregaParams({required this.ventaId, this.entregaIds, this.nuevaFecha});

  final String ventaId;

  /// Las filas (`entrega.id`) que se entregan; `null`: todo lo pendiente. Entregar solo algunas es la
  /// entrega parcial (27C·04): lo que no se marca sigue pendiente.
  final Set<String>? entregaIds;

  /// Para cuándo queda lo que no se entregó (27C·04, «Nueva fecha»): día y hora de la cita. `null`:
  /// lo que queda se queda **sin fecha** («Sin fecha»).
  final DateTime? nuevaFecha;

  @override
  List<Object?> get props => [ventaId, entregaIds, nuevaFecha];
}

/// Lo que devuelve [CumplirEntregaUseCase]: lo que quedó guardado y qué pasó con el aviso.
final class ResultadoCumplirEntrega extends Equatable {
  const ResultadoCumplirEntrega({
    required this.entrega,
    this.recordatorio,
    this.recordatorioCancelado,
  });

  final EntregaCumplida entrega;

  /// Qué pasó con el recordatorio de la fecha nueva; `null` si no hubo fecha nueva o su hora ya pasó.
  final ResultadoRecordatorio? recordatorio;

  /// Si el aviso de la cita cumplida se pudo sacar; `null` si la cita no se cumplió. `false`: la
  /// entrega quedó marcada, pero el aviso podría sonar igual.
  final bool? recordatorioCancelado;

  @override
  List<Object?> get props => [entrega, recordatorio, recordatorioCancelado];
}

/// HU-VEN-003, «Cumplir entrega pendiente»: marca como entregado lo pendiente de una venta, con la
/// fecha real de hoy, sin pantalla.
///
/// 1. Valida y **no guarda nada** si algo está mal: si se piden filas, al menos una; y una fecha nueva
///    no puede ser de un día que ya pasó.
/// 2. Guarda, en **una transacción local** (el repositorio): las filas pasan a `pendiente = false`
///    con `fecha_entrega`, la cita `ENTREGA` pasa a `CUMPLIDA` (o se mueve a la fecha nueva de lo que
///    quedó), sus jobs de sync y el color de la casa (entregada y con saldo: cobranza pendiente;
///    entregada y sin saldo: venta completa).
/// 3. Saca el recordatorio de la cita cumplida o reprograma el de la fecha nueva. Va **después** de la
///    transacción y nunca hace fallar el guardado.
///
/// Es idempotente: marcar de nuevo lo ya entregado no escribe nada ([EntregaCumplida.yaEstaba]).
/// Todo es local: sin red se completa.
final class CumplirEntregaUseCase
    implements UseCase<ResultadoCumplirEntrega, CumplirEntregaParams> {
  CumplirEntregaUseCase(
    this._repository,
    this._recordatorios, {
    required this._generarId,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final EntregaRepository _repository;
  final Recordatorios _recordatorios;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// No se eligió ningún producto para marcar como entregado. Texto a confirmar.
  static const sinProductos = 'Elegí al menos un producto para marcar como entregado.';

  @override
  Future<Either<Failure, ResultadoCumplirEntrega>> call(CumplirEntregaParams params) async {
    final ventaId = params.ventaId.trim();
    final ahora = _ahora();
    final nueva = params.nuevaFecha;

    final campos = <String, String>{
      if (ventaId.isEmpty) 'venta': 'Falta la venta que se entrega.',
      if (params.entregaIds != null && params.entregaIds!.isEmpty) 'productos': sinProductos,
      if (nueva != null && DiferirEntregaUseCase.esDiaPasado(nueva, ahora))
        'fecha': DiferirEntregaUseCase.fechaPasada,
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final hecha = await _repository.cumplir(
      ventaId,
      ahora: ahora,
      idDeLaCita: _generarId(),
      entregaIds: params.entregaIds,
      nuevaFecha: nueva,
    );
    return hecha.fold((falla) async => Left<Failure, ResultadoCumplirEntrega>(falla), (
      entrega,
    ) async {
      final cita = entrega.cita;
      if (cita == null) return Right(ResultadoCumplirEntrega(entrega: entrega));
      if (entrega.citaCumplida) {
        return Right(
          ResultadoCumplirEntrega(
            entrega: entrega,
            recordatorioCancelado: await _sacarRecordatorio(cita.id),
          ),
        );
      }
      if (entrega.citaConFechaNueva) {
        return Right(
          ResultadoCumplirEntrega(entrega: entrega, recordatorio: await _programar(entrega, ahora)),
        );
      }
      return Right(ResultadoCumplirEntrega(entrega: entrega));
    });
  }

  Future<ResultadoRecordatorio?> _programar(EntregaCumplida entrega, DateTime ahora) async {
    final cita = entrega.cita!;
    try {
      if (cita.fechaProgramada.isBefore(_alMinuto(ahora))) {
        await _recordatorios.cancelar(cita.id);
        return null;
      }
      return await _recordatorios.programar(
        RecordatorioDeVisita(
          agendaId: cita.id,
          tipo: cita.tipo,
          direccion: entrega.direccion,
          fechaProgramada: cita.fechaProgramada,
        ),
      );
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ENTREGA_RECORDATORIO',
        'no se pudo programar el recordatorio de la entrega',
        {'agenda_id': cita.id, 'error': e.runtimeType.toString()},
      );
      return ResultadoRecordatorio.noSePudo;
    }
  }

  /// `Recordatorios.cancelar` no lanza, pero una falla del plugin nunca debe deshacer una entrega ya
  /// marcada: cualquier excepción cuenta como «no se pudo».
  Future<bool> _sacarRecordatorio(String agendaId) async {
    try {
      return await _recordatorios.cancelar(agendaId);
    } on Object {
      return false;
    }
  }

  static DateTime _alMinuto(DateTime t) => t.subtract(
    Duration(seconds: t.second, milliseconds: t.millisecond, microseconds: t.microsecond),
  );
}
