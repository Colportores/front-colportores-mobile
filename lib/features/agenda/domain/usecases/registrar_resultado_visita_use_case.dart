import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/nota_de_campo.dart';
import '../entities/visita.dart';
import '../entities/visita_guardada.dart';
import '../repositories/agenda_repository.dart';

/// Los dos ids (UUID v7) de un registro de resultado: la visita y su nota. La pantalla los genera
/// **una vez por formulario** y los repite en cada intento, así que un doble toque o un reintento tras
/// una falla no guarda la visita dos veces (la segunda llamada devuelve la que ya estaba).
final class IdsResultadoVisita extends Equatable {
  const IdsResultadoVisita({required this.visita, required this.nota});

  final String visita;

  /// Solo se usa si hay nota.
  final String nota;

  @override
  List<Object?> get props => [visita, nota];
}

/// Parámetros de [RegistrarResultadoVisitaUseCase].
final class RegistrarResultadoVisitaParams extends Equatable {
  const RegistrarResultadoVisitaParams({
    required this.ids,
    required this.espacioId,
    this.espacioPersonaId,
    required this.colportorId,
    required this.resultado,
    this.agendaId,
    this.jornadaId,
    this.nota = '',
  });

  final IdsResultadoVisita ids;

  /// FK a `espacio.id`: dónde fue la visita (la casa, o el departamento de un edificio). Es
  /// obligatoria: la visita cuelga del espacio (migración 0069 del servidor).
  final String espacioId;

  /// FK a `espacio_persona.id`: con quién fue la visita, **si se sabe** (decisión «Sin persona» de
  /// Cristian, 23/10: `No contestó`, `Rechazo` y una entrevista agendada sin nombre no la tienen).
  /// `null` o en blanco: la visita queda sin persona.
  final String? espacioPersonaId;

  /// UUID del usuario con la sesión iniciada (`created_by` y `colportor_id`).
  final String colportorId;

  final TipoResultadoVisita resultado;

  /// La agenda que la visita viene a cumplir, si la casa tenía una. `null` o en blanco: visita
  /// espontánea (se crea su agenda ya cumplida).
  final String? agendaId;

  /// La jornada abierta, si la hay (opcional, como en el servidor).
  final String? jornadaId;

  /// La nota opcional, local-only: en blanco no crea ninguna.
  final String nota;

  /// Lleva la nota (dato personal): nunca debe salir en un log ni en un `toString`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    ids,
    espacioId,
    espacioPersonaId,
    colportorId,
    resultado,
    agendaId,
    jornadaId,
    nota,
  ];
}

/// A dónde sigue la colportora después de guardar un resultado: el **punto de enganche** de los flujos
/// que vienen después (S9), sin la navegación.
enum SeguimientoDeVisita {
  /// No sigue nada: se vuelve al mapa (o a la hoja de la casa).
  ninguno,

  /// `COBRANZA`: sigue al cobro (HU-COB, C·08 de la vista 39).
  cobro,

  /// `VENTA`: sigue al flujo de venta (HU-VEN-001, S9).
  venta;

  /// El seguimiento que corresponde a [resultado].
  static SeguimientoDeVisita de(TipoResultadoVisita resultado) => switch (resultado) {
    TipoResultadoVisita.venta => venta,
    TipoResultadoVisita.cobranza => cobro,
    TipoResultadoVisita.noContesto ||
    TipoResultadoVisita.rechazo ||
    TipoResultadoVisita.entrevista => ninguno,
  };
}

/// Lo que devuelve [RegistrarResultadoVisitaUseCase]: la visita guardada (con el aviso de su agenda,
/// si lo hay) y a dónde sigue la colportora.
final class ResultadoVisitaRegistrado extends Equatable {
  const ResultadoVisitaRegistrado({required this.guardada, required this.seguimiento});

  final VisitaGuardada guardada;

  final SeguimientoDeVisita seguimiento;

  @override
  List<Object?> get props => [guardada, seguimiento];
}

/// HU-VIS-005 — Registrar el resultado de una visita (`VENTA`, `NO_CONTESTO`, `RECHAZO`,
/// `ENTREVISTA`, `COBRANZA`), sin pantalla.
///
/// 1. Valida: ids, espacio y colportor. Sin alguno, `Left(FailureValidacion)` con el detalle por
///    campo (`ids`, `espacio`, `colportorId`) y no toca la DB. La persona es opcional.
/// 2. Arma la visita (fecha = ahora, resultado, jornada) y su nota opcional y se las pasa al
///    repositorio, que en **una transacción local**: guarda la visita, cierra la agenda que cumple
///    (o, sin agenda, crea una ya `CUMPLIDA`: visita espontánea), guarda la nota, encola visita y
///    agenda (y `house_status`) sin la nota, y recalcula el color de la casa.
/// 3. Dice a dónde sigue ([SeguimientoDeVisita]): `VENTA` al flujo de venta (S9).
///
/// Todo es local: sin red se completa. Qué resultados cuentan como presentación
/// (`TipoResultadoVisita.cuentaComoPresentacion`) y cuáles cumplen la agenda
/// (`TipoResultadoVisita.cumpleLaAgenda`) lo dice el resultado mismo.
///
/// **Venta sin completar (R44, vista 39)**: «si la venta no se completa, el resultado no se guarda».
/// Este caso de uso guarda lo que le piden; el flujo de venta (S9) decide cuándo llamarlo.
final class RegistrarResultadoVisitaUseCase
    implements UseCase<ResultadoVisitaRegistrado, RegistrarResultadoVisitaParams> {
  /// [_generarId] se pasa como `generarId:` (parámetro nombrado privado, Dart ≥ 3.10).
  RegistrarResultadoVisitaUseCase(
    this._repository, {
    required this._generarId,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final AgendaRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  /// Los ids de un formulario de resultado nuevo (ver [IdsResultadoVisita]).
  IdsResultadoVisita nuevosIds() => IdsResultadoVisita(visita: _generarId(), nota: _generarId());

  @override
  Future<Either<Failure, ResultadoVisitaRegistrado>> call(
    RegistrarResultadoVisitaParams params,
  ) async {
    final espacioId = params.espacioId.trim();
    final espacioPersonaId = params.espacioPersonaId?.trim();
    final colportorId = params.colportorId.trim();
    final ids = params.ids;

    final campos = <String, String>{
      if (ids.visita.trim().isEmpty || ids.nota.trim().isEmpty)
        'ids': 'Falta el identificador de la visita',
      if (espacioId.isEmpty) 'espacio': 'Falta la casa de la visita',
      if (colportorId.isEmpty) 'colportorId': 'No hay un colportor para registrar la visita',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final ahora = _ahora();
    Auditoria auditoria() => Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId);
    final textoNota = params.nota.trim();
    final agendaId = params.agendaId?.trim();
    final jornadaId = params.jornadaId?.trim();

    final guardada = await _repository.registrarVisita(
      Visita(
        id: ids.visita.trim(),
        espacioId: espacioId,
        espacioPersonaId: espacioPersonaId == null || espacioPersonaId.isEmpty
            ? null
            : espacioPersonaId,
        fecha: ahora,
        tipoResultado: params.resultado,
        colportorId: colportorId,
        jornadaId: jornadaId == null || jornadaId.isEmpty ? null : jornadaId,
        auditoria: auditoria(),
      ),
      agendaId: agendaId == null || agendaId.isEmpty ? null : agendaId,
      nota: textoNota.isEmpty
          ? null
          : NotaDeCampo(id: ids.nota.trim(), texto: textoNota, auditoria: auditoria()),
    );
    return guardada.map(
      (g) => ResultadoVisitaRegistrado(
        guardada: g,
        seguimiento: SeguimientoDeVisita.de(g.visita.tipoResultado),
      ),
    );
  }
}

/// Parámetros de [DeshacerResultadoVisitaUseCase]: la visita y lo que su registro tocó (los dos
/// ids vienen de [VisitaGuardada]).
final class DeshacerResultadoVisitaParams extends Equatable {
  const DeshacerResultadoVisitaParams({
    required this.visitaId,
    this.agendaCreadaId,
    this.agendaAfectadaId,
  });

  /// Arma los parámetros desde lo que devolvió el registro.
  factory DeshacerResultadoVisitaParams.de(VisitaGuardada guardada) =>
      DeshacerResultadoVisitaParams(
        visitaId: guardada.visita.id,
        agendaCreadaId: guardada.agendaCreadaId,
        agendaAfectadaId: guardada.agendaAfectadaId,
      );

  final String visitaId;
  final String? agendaCreadaId;
  final String? agendaAfectadaId;

  @override
  List<Object?> get props => [visitaId, agendaCreadaId, agendaAfectadaId];
}

/// El «Deshacer» de «Guardado» (vista 39, R·01): da de baja la visita recién guardada, con sus notas,
/// y deja la agenda como estaba. Es un `delete` que viaja por el sync (nada se borra del teléfono).
/// Deshacer dos veces no escribe nada la segunda.
final class DeshacerResultadoVisitaUseCase
    implements UseCase<Visita, DeshacerResultadoVisitaParams> {
  DeshacerResultadoVisitaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AgendaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Visita>> call(DeshacerResultadoVisitaParams params) {
    final visitaId = params.visitaId.trim();
    if (visitaId.isEmpty) {
      return Future.value(
        const Left(FailureValidacion(campos: {'visita': 'Falta el identificador de la visita'})),
      );
    }
    String? limpio(String? id) => id == null || id.trim().isEmpty ? null : id.trim();
    return _repository.deshacerVisita(
      visitaId,
      agendaCreadaId: limpio(params.agendaCreadaId),
      agendaAfectadaId: limpio(params.agendaAfectadaId),
      ahora: _ahora(),
    );
  }
}
