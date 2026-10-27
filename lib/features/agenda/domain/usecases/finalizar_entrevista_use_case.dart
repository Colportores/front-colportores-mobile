import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/entrevista_en_curso.dart';
import '../entities/visita.dart';
import '../repositories/borrador_de_nota_de_entrevista.dart';
import '../repositories/entrevista_en_curso_repository.dart';
import '../services/destino_de_entrevista.dart';
import '../services/horas_de_entrevista.dart';
import 'registrar_resultado_visita_use_case.dart';

/// Parámetros de [FinalizarEntrevistaUseCase].
final class FinalizarEntrevistaParams extends Equatable {
  const FinalizarEntrevistaParams({
    required this.ids,
    required this.espacioId,
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
    espacioId: en.espacioId,
    espacioPersonaId: en.espacioPersonaId,
    colportorId: en.colportorId,
    entrada: entrada,
    salida: salida,
    agendaId: en.agendaId,
    jornadaId: en.jornadaId,
    nota: nota,
  );

  final IdsResultadoVisita ids;

  /// El espacio (casa o depto) donde fue la entrevista; si en el teléfono cambió, la visita va al
  /// vigente (ver [ResolverDestinoDeEntrevista]).
  final String espacioId;
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
    espacioId,
    espacioPersonaId,
    colportorId,
    entrada,
    salida,
    agendaId,
    jornadaId,
    nota,
  ];
}

/// No hay dónde guardar la entrevista: ni la casa ni el depto siguen en el teléfono. La entrevista
/// se descartó (con su nota en borrador) para que la jornada no quede trabada.
const entrevistaSinLugar = FailureValidacion(
  campos: {'espacio': 'La casa de esta entrevista ya no está en tu teléfono.'},
  mensaje: 'La casa de esta entrevista ya no está en tu teléfono, así que se cerró sin guardar.',
);

/// HU-VIS-005, vista 39 R·06 y R·07: «No, guardar y volver al mapa». Guarda la visita como
/// `ENTREVISTA` («Entrevista dada», verde) y borra la entrevista en curso del teléfono.
///
/// 1. Valida las horas ([HorasDeEntrevista]): la salida no es antes de la entrada ni futura, y no
///    pasa de 12 h. Con horas inválidas no guarda nada: `Left(FailureValidacion)` con el detalle.
/// 2. **Se guarda igual** («Sin salida», decisión de Cristian, 25/10): busca dónde cuelga hoy la
///    visita ([ResolverDestinoDeEntrevista]). Si la persona se unió con otra, va a la que quedó; si
///    le dieron de baja, la visita queda de la casa o del depto **sin persona**. Si ni la casa ni el
///    depto siguen en el teléfono no hay dónde guardarla: la entrevista se descarta (con el borrador
///    de su nota) y devuelve [entrevistaSinLugar], para que la jornada no quede trabada.
/// 3. Registra la visita con [RegistrarResultadoVisitaUseCase] (los ids de la entrevista: un
///    reintento tras una falla, o un doble toque, no la guarda dos veces). Su nota es el texto final
///    y reemplaza al borrador de la entrevista.
/// 4. Borra la entrevista en curso. Si **eso** falla, devuelve `Left`: la visita ya quedó guardada y
///    el reintento (mismos ids) la encuentra y vuelve a intentar el borrado.
///
/// **Las horas de entrada y salida no se guardan en la visita** hasta #466 (esperan las columnas
/// de backend-supabase#132): se validan y se usan para el aviso y el resumen.
///
/// Para «Sí, registrar la venta» este caso de uso **no se llama**: si la venta no se completa el
/// resultado no se guarda (R44, vista 39), y la entrevista sigue en curso hasta que el flujo de
/// venta (S9, #428) decida.
final class FinalizarEntrevistaUseCase
    implements UseCase<ResultadoVisitaRegistrado, FinalizarEntrevistaParams> {
  FinalizarEntrevistaUseCase(
    this._registrar,
    this._repository,
    this._destino,
    this._borrador, {
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final RegistrarResultadoVisitaUseCase _registrar;
  final EntrevistaEnCursoRepository _repository;
  final ResolverDestinoDeEntrevista _destino;
  final BorradorDeNotaDeEntrevista _borrador;
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

    // La entrevista empezó con una casa y una persona elegidas (R·04): sin alguna de las dos no hay
    // entrevista que guardar. «Sin persona» es otra cosa: es lo que queda si la persona ya no está.
    final campos = <String, String>{
      if (params.espacioId.trim().isEmpty) 'espacio': 'Falta la casa de la entrevista',
      if (params.espacioPersonaId.trim().isEmpty)
        'persona': 'Elegí con quién fue la entrevista para guardarla.',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final DestinoDeEntrevista? destino;
    try {
      destino = await _destino.resolver(
        espacioId: params.espacioId.trim(),
        espacioPersonaId: params.espacioPersonaId.trim(),
      );
    } on Object catch (e) {
      _log.error(
        LogModulo.agenda,
        'ENTREVISTA_DESTINO',
        'no se pudo leer dónde cuelga la entrevista',
        {'tipo': e.runtimeType.toString()},
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
    if (destino == null) return _descartar(params);

    final guardada = await _registrar(
      RegistrarResultadoVisitaParams(
        ids: params.ids,
        espacioId: destino.espacioId,
        espacioPersonaId: destino.espacioPersonaId,
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

  /// No hay dónde guardar la visita: se suelta la entrevista y su borrador de nota. Si el almacén
  /// falla, devuelve esa falla y la entrevista sigue (el reintento lo vuelve a intentar).
  Future<Either<Failure, ResultadoVisitaRegistrado>> _descartar(
    FinalizarEntrevistaParams params,
  ) async {
    try {
      await _repository.borrar(params.colportorId.trim(), idVisita: params.ids.visita.trim());
      await _borrador.borrar(params.ids.nota.trim());
    } on Object catch (e) {
      _log.error(
        LogModulo.agenda,
        'ENTREVISTA_DESCARTAR',
        'no se pudo soltar la entrevista cuya casa ya no está',
        {'tipo': e.runtimeType.toString()},
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
    _log.warn(
      LogModulo.agenda,
      'ENTREVISTA_SIN_LUGAR',
      'la casa de la entrevista ya no está: se descartó',
    );
    return const Left(entrevistaSinLugar);
  }
}
