import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/agenda.dart';
import '../entities/franja_horaria.dart';
import '../entities/nota_de_campo.dart';
import '../entities/recordatorio_de_visita.dart';
import '../entities/tipo_agenda.dart';
import '../repositories/agenda_repository.dart';
import '../services/recordatorios.dart';

/// Los dos ids (UUID v7) de un formulario de agendar: la agenda y su nota. La pantalla los genera
/// **una vez por formulario** y los repite en cada intento, así que un doble toque o un reintento
/// tras una falla no guarda la agenda dos veces (la segunda llamada devuelve la que ya estaba).
final class IdsAgendarVisita extends Equatable {
  const IdsAgendarVisita({required this.agenda, required this.nota});

  final String agenda;

  /// Solo se usa si hay nota.
  final String nota;

  @override
  List<Object?> get props => [agenda, nota];
}

/// Parámetros de [AgendarVisitaUseCase].
final class AgendarVisitaParams extends Equatable {
  const AgendarVisitaParams({
    required this.ids,
    required this.espacioId,
    this.espacioPersonaId,
    required this.colportorId,
    required this.tipo,
    required this.fechaProgramada,
    this.franja,
    this.esEstricta = false,
    this.nota = '',
    this.direccion = '',
    this.confirmoHoraPasada = false,
  });

  final IdsAgendarVisita ids;

  /// FK a `espacio.id`: la casa o el depto de la visita. Obligatorio: la agenda cuelga del espacio.
  final String espacioId;

  /// FK a `espacio_persona.id`: con quién es la visita, si se sabe. `null` o en blanco: queda sin
  /// persona (decisión «Sin persona», 23/10).
  final String? espacioPersonaId;

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  final TipoAgenda tipo;

  /// Cuándo es la visita (hora local, al minuto; la entidad la lleva a UTC).
  final DateTime fechaProgramada;

  /// La franja elegida o aceptada (`agenda.slot_codigo`); `null`: sin franja.
  final FranjaHoraria? franja;

  /// «Entrevista estricta» (hora fija acordada). Hoy ninguna pantalla lo pide: ver las pendientes
  /// de #408.
  final bool esEstricta;

  /// La nota opcional, local-only: en blanco no crea ninguna.
  final String nota;

  /// La dirección que lleva el aviso («Av. Italia 1234»); puede ir vacía.
  final String direccion;

  /// La persona ya vio «Esa hora ya pasó» y eligió «Agendar igual» (HU-VIS-001, «Edge - hora ya
  /// pasó»).
  final bool confirmoHoraPasada;

  /// Lleva la nota (dato personal): nunca debe salir en un log ni en un `toString`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    ids,
    espacioId,
    espacioPersonaId,
    colportorId,
    tipo,
    fechaProgramada,
    franja,
    esEstricta,
    nota,
    direccion,
    confirmoHoraPasada,
  ];
}

/// Lo que devuelve [AgendarVisitaUseCase] cuando no hay falla.
sealed class ResultadoAgendar extends Equatable {
  const ResultadoAgendar();
}

/// La agenda quedó guardada.
final class VisitaAgendada extends ResultadoAgendar {
  const VisitaAgendada({required this.agenda, required this.recordatorio});

  final Agenda agenda;

  /// Qué pasó con el aviso. `null`: no se intentó, porque la hora ya había pasado y la persona
  /// confirmó agendar igual (23A·03: «Agendar igual no programa el recordatorio»).
  final ResultadoRecordatorio? recordatorio;

  @override
  List<Object?> get props => [agenda, recordatorio];
}

/// La hora ya pasó y la persona todavía no confirmó: no se guardó nada. La pantalla advierte y, si
/// ella insiste, vuelve a pedir con `confirmoHoraPasada`.
final class HoraPasadaSinConfirmar extends ResultadoAgendar {
  const HoraPasadaSinConfirmar({required this.ahora});

  /// El reloj con que se comparó (para decir «son las 14:35»).
  final DateTime ahora;

  @override
  List<Object?> get props => [ahora];
}

/// HU-VIS-001 — Agendar una visita (entrevista o cobranza), sin pantalla.
///
/// 1. Valida: ids, espacio y colportor. Sin alguno, `Left(FailureValidacion)` con el detalle por
///    campo y no toca la DB.
/// 2. Si la hora ya pasó (se compara al minuto) y la persona no lo confirmó, no guarda nada y
///    devuelve [HoraPasadaSinConfirmar].
/// 3. Guarda la agenda `PROGRAMADA` y su nota opcional; el repositorio lo hace en **una transacción
///    local** que la encola para el sync y recalcula el color de la casa (`house_status`).
/// 4. Programa el recordatorio con la dirección de la visita, salvo que la hora haya pasado.
///    Programar nunca hace fallar el guardado: lo que pasó con el aviso va en
///    [VisitaAgendada.recordatorio].
///
/// Todo es local: sin red se completa.
final class AgendarVisitaUseCase implements UseCase<ResultadoAgendar, AgendarVisitaParams> {
  /// [_generarId] se pasa como `generarId:` (parámetro nombrado privado, Dart ≥ 3.10).
  AgendarVisitaUseCase(
    this._repository,
    this._recordatorios, {
    required this._generarId,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final AgendaRepository _repository;
  final Recordatorios _recordatorios;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Los ids de un formulario nuevo (ver [IdsAgendarVisita]).
  IdsAgendarVisita nuevosIds() => IdsAgendarVisita(agenda: _generarId(), nota: _generarId());

  @override
  Future<Either<Failure, ResultadoAgendar>> call(AgendarVisitaParams params) async {
    final espacioId = params.espacioId.trim();
    final colportorId = params.colportorId.trim();
    final ids = params.ids;

    final campos = <String, String>{
      if (ids.agenda.trim().isEmpty || ids.nota.trim().isEmpty)
        'ids': 'Falta el identificador de la agenda',
      if (espacioId.isEmpty) 'espacio': 'Falta la casa de la visita',
      if (colportorId.isEmpty) 'colportorId': 'No hay un colportor para agendar la visita',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final ahora = _ahora();
    final horaPasada = params.fechaProgramada.isBefore(_alMinuto(ahora));
    if (horaPasada && !params.confirmoHoraPasada) {
      return Right(HoraPasadaSinConfirmar(ahora: ahora));
    }

    final personaId = params.espacioPersonaId?.trim();
    Auditoria auditoria() => Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId);
    final textoNota = params.nota.trim();

    final guardada = await _repository.agendar(
      Agenda(
        id: ids.agenda.trim(),
        espacioId: espacioId,
        espacioPersonaId: personaId == null || personaId.isEmpty ? null : personaId,
        tipo: params.tipo,
        fechaProgramada: params.fechaProgramada,
        slotCodigo: params.franja?.codigo,
        esEstricta: params.esEstricta,
        colportorId: colportorId,
        auditoria: auditoria(),
      ),
      nota: textoNota.isEmpty
          ? null
          : NotaDeCampo(id: ids.nota.trim(), texto: textoNota, auditoria: auditoria()),
    );
    Failure? falla;
    Agenda? agenda;
    guardada.fold((f) => falla = f, (a) => agenda = a);
    final guardadaOk = agenda;
    if (guardadaOk == null) return Left(falla ?? const FailureInesperado());
    // Una hora pasada confirmada no promete un aviso que no va a sonar.
    final recordatorio = horaPasada ? null : await _programar(guardadaOk, params);
    return Right(VisitaAgendada(agenda: guardadaOk, recordatorio: recordatorio));
  }

  Future<ResultadoRecordatorio> _programar(Agenda agenda, AgendarVisitaParams params) async {
    try {
      return await _recordatorios.programar(
        RecordatorioDeVisita(
          agendaId: agenda.id,
          tipo: agenda.tipo,
          direccion: params.direccion,
          fechaProgramada: agenda.fechaProgramada,
        ),
      );
    } on Object catch (e) {
      // El puerto no lanza; si lo hiciera, la agenda ya está guardada y no se pierde por eso. Nada de
      // la dirección al log (convenciones §7.5).
      AppLogger.instance.warn(
        LogModulo.agenda,
        'AGENDAR_RECORDATORIO',
        'no se pudo programar el recordatorio de la agenda',
        {'agenda_id': agenda.id, 'error': e.runtimeType.toString()},
      );
      return ResultadoRecordatorio.noSePudo;
    }
  }

  /// [t] sin los segundos (la hora se elige al minuto): elegir el minuto en curso no es «pasada».
  static DateTime _alMinuto(DateTime t) => t.subtract(
    Duration(seconds: t.second, milliseconds: t.millisecond, microseconds: t.microsecond),
  );
}
