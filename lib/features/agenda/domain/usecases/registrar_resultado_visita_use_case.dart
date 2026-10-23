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
    required this.espacioPersonaId,
    required this.colportorId,
    required this.resultado,
    this.agendaId,
    this.jornadaId,
    this.nota = '',
  });

  final IdsResultadoVisita ids;

  /// FK a `espacio_persona.id`: con quién fue la visita. Es obligatoria (el servidor exige
  /// `espacio_persona_id NOT NULL`): la visita sin persona espera la decisión P3 de #151 y no se
  /// guarda con una persona vacía.
  final String espacioPersonaId;

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
  /// No sigue nada: se vuelve a la hoja de la casa.
  ninguno,

  /// `VENTA`: sigue al flujo de venta (HU-VEN-001, S9).
  venta;

  /// El seguimiento que corresponde a [resultado]. `COBRANZA` (que seguiría al cobro, HU-COB) no
  /// existe todavía: espera la decisión P2 de #151.
  static SeguimientoDeVisita de(TipoResultadoVisita resultado) => switch (resultado) {
    TipoResultadoVisita.venta => venta,
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
/// `ENTREVISTA`), sin pantalla.
///
/// 1. Valida: ids, persona y colportor. Sin alguno, `Left(FailureValidacion)` con el detalle por
///    campo (`ids`, `persona`, `colportorId`) y no toca la DB.
/// 2. Arma la visita (fecha = ahora, resultado, jornada) y su nota opcional y se las pasa al
///    repositorio, que en **una transacción local**: guarda la visita, cierra la agenda que cumple
///    (o, sin agenda, crea una ya `COMPLETADA`: visita espontánea), guarda la nota, encola visita y
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
    final espacioPersonaId = params.espacioPersonaId.trim();
    final colportorId = params.colportorId.trim();
    final ids = params.ids;

    final campos = <String, String>{
      if (ids.visita.trim().isEmpty || ids.nota.trim().isEmpty)
        'ids': 'Falta el identificador de la visita',
      if (espacioPersonaId.isEmpty)
        'persona': 'Elegí a la persona de la visita para guardar el resultado.',
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
        espacioPersonaId: espacioPersonaId,
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
