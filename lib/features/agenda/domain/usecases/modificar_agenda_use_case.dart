import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/instante.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/agenda.dart';
import '../entities/cambios_de_agenda.dart';
import '../entities/estado_agenda.dart';
import '../entities/franja_horaria.dart';
import '../entities/motivo_rechazo_agenda.dart';
import '../entities/recordatorio_de_visita.dart';
import '../entities/tipo_agenda.dart';
import '../repositories/agenda_repository.dart';
import '../services/recordatorios.dart';

/// Parámetros de [ModificarAgendaUseCase].
final class ModificarAgendaParams extends Equatable {
  const ModificarAgendaParams({
    required this.agendaId,
    required this.idNota,
    required this.tipo,
    required this.fechaProgramada,
    this.franja,
    this.nota = '',
    this.direccion = '',
    this.confirmoHoraPasada = false,
  });

  final String agendaId;

  /// El id de la nota si hay que crearla: el formulario lo genera una vez y lo repite en cada intento.
  final String idNota;

  final TipoAgenda tipo;

  /// Cuándo es la visita (hora local, al minuto).
  final DateTime fechaProgramada;

  /// La franja elegida o aceptada (`agenda.slot_codigo`); `null`: sin franja.
  final FranjaHoraria? franja;

  /// El texto de la nota como quedó en el formulario; en blanco borra la que había.
  final String nota;

  /// La dirección que lleva el aviso («Av. Italia 1234»); puede ir vacía.
  final String direccion;

  /// La persona ya vio «Esa hora ya pasó» y eligió «Guardar igual».
  final bool confirmoHoraPasada;

  /// Lleva la nota (dato personal): nunca debe salir en un log ni en un `toString`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    agendaId,
    idNota,
    tipo,
    fechaProgramada,
    franja,
    nota,
    direccion,
    confirmoHoraPasada,
  ];
}

/// Lo que devuelve [ModificarAgendaUseCase] cuando no hay falla.
sealed class ResultadoModificar extends Equatable {
  const ResultadoModificar();
}

/// La agenda quedó modificada.
final class AgendaModificada extends ResultadoModificar {
  const AgendaModificada({required this.agenda, required this.recordatorio});

  final Agenda agenda;

  /// Qué pasó con el aviso. `null`: no se intentó, porque la hora nueva ya pasó y la persona confirmó
  /// guardar igual (el aviso anterior se sacó para que no suene a destiempo).
  final ResultadoRecordatorio? recordatorio;

  @override
  List<Object?> get props => [agenda, recordatorio];
}

/// La hora nueva ya pasó y la persona todavía no lo confirmó: no se guardó nada.
final class HoraPasadaSinConfirmarAlModificar extends ResultadoModificar {
  const HoraPasadaSinConfirmarAlModificar({required this.ahora});

  /// El reloj con que se comparó (para decir «son las 14:35»).
  final DateTime ahora;

  @override
  List<Object?> get props => [ahora];
}

/// HU-VIS-003 — Modificar una agenda `PROGRAMADA` (tipo, día y hora, franja y nota), sin pantalla.
///
/// 1. Valida los ids. Sin alguno, `Left(FailureValidacion)` y no toca la DB.
/// 2. Lee la agenda. Una agenda que no está, o que ya no está programada (cumplida, no cumplida o
///    cancelada), es un `Left(FailureValidacion)` con el campo `agenda`.
/// 3. Si la hora **cambió** a una que ya pasó y la persona no lo confirmó, no guarda y devuelve
///    [HoraPasadaSinConfirmarAlModificar]. Una agenda que ya estaba vencida y no cambia de hora (solo
///    se corrige el tipo o la nota) no vuelve a preguntar.
/// 4. Guarda en **una transacción local** (el repositorio): la fila, su job de sync, la nota, el
///    `audit_log` local y el color de la casa (cambiar de ENTREVISTA a COBRANZA lo recalcula).
/// 5. Reprograma el recordatorio con la hora nueva (el mismo `agenda.id` lo reemplaza); si la hora
///    quedó en el pasado, saca el que había. Va **después** de la transacción y nunca hace fallar el
///    guardado: lo que pasó con el aviso va en [AgendaModificada.recordatorio].
///
/// Todo es local: sin red se completa. Guardar lo mismo que ya había no escribe nada (un doble toque
/// o un reintento no duplican nada).
final class ModificarAgendaUseCase implements UseCase<ResultadoModificar, ModificarAgendaParams> {
  ModificarAgendaUseCase(this._repository, this._recordatorios, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AgendaRepository _repository;
  final Recordatorios _recordatorios;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, ResultadoModificar>> call(ModificarAgendaParams params) async {
    final agendaId = params.agendaId.trim();
    final idNota = params.idNota.trim();
    final campos = <String, String>{
      if (agendaId.isEmpty) 'agenda': 'Falta el identificador de la agenda',
      if (idNota.isEmpty) 'ids': 'Falta el identificador de la nota',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final leida = await _repository.obtenerDetalle(agendaId);
    Failure? falla;
    Agenda? actual;
    leida.fold((f) => falla = f, (d) => actual = d?.agenda);
    final vigente = actual;
    if (vigente == null) {
      return Left(
        falla ??
            FailureValidacion(
              campos: {
                MotivoRechazoAgenda.agendaInexistente.campo:
                    MotivoRechazoAgenda.agendaInexistente.mensaje,
              },
            ),
      );
    }
    if (vigente.estado != EstadoAgenda.programada) {
      return Left(
        FailureValidacion(
          campos: {
            MotivoRechazoAgenda.agendaCerrada.campo: MotivoRechazoAgenda.agendaCerrada.mensaje,
          },
        ),
      );
    }

    final ahora = _ahora();
    final horaPasada = params.fechaProgramada.isBefore(_alMinuto(ahora));
    final cambiaLaHora = instanteMs(params.fechaProgramada) != vigente.fechaProgramada;
    if (horaPasada && cambiaLaHora && !params.confirmoHoraPasada) {
      return Right(HoraPasadaSinConfirmarAlModificar(ahora: ahora));
    }

    final guardada = await _repository.modificar(
      CambiosDeAgenda(
        agendaId: agendaId,
        tipo: params.tipo,
        fechaProgramada: params.fechaProgramada,
        slotCodigo: params.franja?.codigo,
        nota: params.nota,
        idNota: idNota,
      ),
      ahora: ahora,
    );
    Agenda? agenda;
    guardada.fold((f) => falla = f, (a) => agenda = a);
    final modificada = agenda;
    if (modificada == null) return Left(falla ?? const FailureInesperado());
    return Right(
      AgendaModificada(
        agenda: modificada,
        recordatorio: horaPasada
            ? await _sacar(modificada)
            : await _reprogramar(modificada, params.direccion),
      ),
    );
  }

  Future<ResultadoRecordatorio> _reprogramar(Agenda agenda, String direccion) async {
    try {
      return await _recordatorios.programar(
        RecordatorioDeVisita(
          agendaId: agenda.id,
          tipo: agenda.tipo,
          direccion: direccion,
          fechaProgramada: agenda.fechaProgramada,
        ),
      );
    } on Object catch (e) {
      // El puerto no lanza; si lo hiciera, la agenda ya está guardada y no se pierde por eso. Nada de
      // la dirección al log (convenciones §7.5).
      AppLogger.instance.warn(
        LogModulo.agenda,
        'MODIFICAR_RECORDATORIO',
        'no se pudo reprogramar el recordatorio de la agenda',
        {'agenda_id': agenda.id, 'error': e.runtimeType.toString()},
      );
      return ResultadoRecordatorio.noSePudo;
    }
  }

  /// La hora nueva ya pasó: el aviso viejo (de la hora anterior) no tiene que sonar. Devuelve `null`
  /// (no se promete ningún aviso).
  Future<ResultadoRecordatorio?> _sacar(Agenda agenda) async {
    try {
      await _recordatorios.cancelar(agenda.id);
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.agenda,
        'MODIFICAR_RECORDATORIO',
        'no se pudo sacar el recordatorio de la agenda',
        {'agenda_id': agenda.id, 'error': e.runtimeType.toString()},
      );
    }
    return null;
  }

  /// [t] sin los segundos (la hora se elige al minuto): elegir el minuto en curso no es «pasada».
  static DateTime _alMinuto(DateTime t) => t.subtract(
    Duration(seconds: t.second, milliseconds: t.millisecond, microseconds: t.microsecond),
  );
}
