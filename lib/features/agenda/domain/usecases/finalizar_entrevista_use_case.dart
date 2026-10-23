import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/entrevista_en_curso.dart';
import '../entities/visita.dart';
import '../repositories/entrevista_en_curso_repository.dart';
import '../services/horas_de_entrevista.dart';
import 'registrar_resultado_visita_use_case.dart';

/// Parámetros de [FinalizarEntrevistaUseCase].
final class FinalizarEntrevistaParams extends Equatable {
  const FinalizarEntrevistaParams({
    required this.ids,
    required this.espacioPersonaId,
    required this.colportorId,
    required this.entrada,
    required this.salida,
    this.agendaId,
    this.jornadaId,
    this.nota = '',
  });

  /// Termina la entrevista [en] curso con las horas que confirmó la colportora.
  factory FinalizarEntrevistaParams.de(
    EntrevistaEnCurso en, {
    required DateTime entrada,
    required DateTime salida,
    String nota = '',
  }) => FinalizarEntrevistaParams(
    ids: en.ids,
    espacioPersonaId: en.espacioPersonaId,
    colportorId: en.colportorId,
    entrada: entrada,
    salida: salida,
    agendaId: en.agendaId,
    jornadaId: en.jornadaId,
    nota: nota,
  );

  final IdsResultadoVisita ids;
  final String espacioPersonaId;
  final String colportorId;
  final DateTime entrada;
  final DateTime salida;
  final String? agendaId;
  final String? jornadaId;

  /// La nota de la visita, local-only: en blanco no crea ninguna.
  final String nota;

  /// Lleva la nota (dato personal): nunca debe salir en un log ni en un `toString`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    ids,
    espacioPersonaId,
    colportorId,
    entrada,
    salida,
    agendaId,
    jornadaId,
    nota,
  ];
}

/// HU-VIS-005, vista 39 R·06 y R·07: «No, guardar y volver al mapa». Guarda la visita como
/// `ENTREVISTA` («Entrevista dada», verde) y borra la entrevista en curso del teléfono.
///
/// 1. Valida las horas ([HorasDeEntrevista]): la salida no es antes de la entrada ni futura, y no
///    pasa de 12 h. Con horas inválidas no guarda nada: `Left(FailureValidacion)` con el detalle.
/// 2. Registra la visita con [RegistrarResultadoVisitaUseCase] (los ids de la entrevista: un
///    reintento tras una falla, o un doble toque, no la guarda dos veces).
/// 3. Borra la entrevista en curso. Si **eso** falla, devuelve `Left`: la visita ya quedó guardada y
///    el reintento (mismos ids) la encuentra y vuelve a intentar el borrado.
///
/// **Las horas de entrada y salida no se guardan en la visita**: el servidor tiene solo `fecha`
/// (pendiente de modelo de datos, issue #450). Se validan y se usan para el aviso y el resumen.
///
/// Para «Sí, registrar la venta» este caso de uso **no se llama**: si la venta no se completa el
/// resultado no se guarda (R44, vista 39), y la entrevista sigue en curso hasta que el flujo de
/// venta (S9, #428) decida.
final class FinalizarEntrevistaUseCase
    implements UseCase<ResultadoVisitaRegistrado, FinalizarEntrevistaParams> {
  FinalizarEntrevistaUseCase(
    this._registrar,
    this._repository, {
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final RegistrarResultadoVisitaUseCase _registrar;
  final EntrevistaEnCursoRepository _repository;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Future<Either<Failure, ResultadoVisitaRegistrado>> call(FinalizarEntrevistaParams params) async {
    final invalida = HorasDeEntrevista.validar(
      entrada: params.entrada,
      salida: params.salida,
      ahora: _ahora(),
    );
    if (invalida != null) return Left(invalida);

    final guardada = await _registrar(
      RegistrarResultadoVisitaParams(
        ids: params.ids,
        espacioPersonaId: params.espacioPersonaId,
        colportorId: params.colportorId,
        resultado: TipoResultadoVisita.entrevista,
        agendaId: params.agendaId,
        jornadaId: params.jornadaId,
        nota: params.nota,
      ),
    );
    if (guardada.isLeft()) return guardada;

    try {
      await _repository.borrar(params.colportorId.trim(), idVisita: params.ids.visita.trim());
    } on Object catch (e) {
      _log.error(
        LogModulo.agenda,
        'ENTREVISTA_FINALIZAR',
        'la visita se guardó pero no se pudo borrar la entrevista en curso',
        {'tipo': e.runtimeType.toString()},
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
    return guardada;
  }
}
