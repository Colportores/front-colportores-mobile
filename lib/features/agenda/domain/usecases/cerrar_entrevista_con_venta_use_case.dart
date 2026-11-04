import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../entities/visita.dart';
import '../repositories/entrevista_en_curso_repository.dart';
import '../services/destino_de_entrevista.dart';
import '../services/horas_de_entrevista.dart';
import 'finalizar_entrevista_use_case.dart';
import 'registrar_resultado_visita_use_case.dart';

/// No hay dónde guardar la venta de la entrevista: ni la casa ni el depto siguen en el teléfono. A
/// diferencia de «No, guardar y volver al mapa» **no se descarta nada**: la entrevista sigue en curso y
/// la colportora decide cómo cerrarla.
const ventaSinLugar = FailureValidacion(
  campos: {'espacio': 'La casa de esta entrevista ya no está en tu teléfono.'},
  mensaje:
      'La casa de esta entrevista ya no está en tu teléfono, así que no se puede registrar la '
      'venta. La entrevista sigue en curso: cerrala con «No, guardar y volver al mapa».',
);

/// La persona de la entrevista ya no está en el teléfono (se dio de baja): una venta se ata a una
/// persona, así que no hay a quién registrársela.
const ventaSinPersona = FailureValidacion(
  campos: {'persona': 'La persona de esta entrevista ya no está en tu teléfono.'},
  mensaje:
      'La persona de esta entrevista ya no está en tu teléfono, así que no se puede registrar la '
      'venta. La entrevista sigue en curso: cerrala con «No, guardar y volver al mapa».',
);

/// Lo que la venta de una entrevista necesita, ya resuelto: dónde y con quién cuelga hoy y la visita
/// `VENTA` que se guarda junto con ella (vista 39, R·06 → vista 27).
final class VentaDeLaEntrevista extends Equatable {
  const VentaDeLaEntrevista({
    required this.espacioId,
    required this.espacioPersonaId,
    required this.colportorId,
    required this.visita,
  });

  /// El espacio vivo donde queda la visita (puede no ser donde empezó la entrevista: una unión).
  final String espacioId;

  /// El vínculo vivo con la persona a la que se le vende.
  final String espacioPersonaId;
  final String colportorId;

  /// La visita `VENTA` que se guarda dentro de la transacción de la venta. Lleva los ids de la
  /// entrevista: un reintento no la guarda dos veces.
  final RegistrarResultadoVisitaParams visita;

  /// El id de la visita: la venta lo lleva como `visita_id` (la visita se guarda antes que ella).
  String get visitaId => visita.ids.visita.trim();

  @override
  List<Object?> get props => [espacioId, espacioPersonaId, colportorId, visita];
}

/// La visita de la venta no se pudo guardar. Se lanza **dentro** de la transacción de la venta para
/// que se revierta entera (R44: si la venta no se completa, el resultado no se guarda). No lleva
/// datos de la persona: solo el tipo de la falla.
final class VisitaDeLaVentaNoGuardada implements Exception {
  const VisitaDeLaVentaNoGuardada(this.falla);

  final Failure falla;

  @override
  String toString() => 'VisitaDeLaVentaNoGuardada(${falla.codigo})';
}

/// «Sí, registrar la venta» de R·06 / R·07 (vista 39, HU-VIS-005, HU-VEN-001): cierra la entrevista
/// **junto con** la venta, en tres tiempos:
///
/// 1. [preparar]: valida las horas y busca dónde cuelga hoy la visita ([ResolverDestinoDeEntrevista]).
///    **No guarda nada.** Si la casa o la persona ya no están, no hay venta posible y la entrevista
///    sigue en curso.
/// 2. [guardarVisita]: lo que corre dentro de la transacción de la venta (`antesDeGuardar`): guarda la
///    visita como `VENTA` con la nota de la entrevista. Si falla, la venta tampoco se guarda.
/// 3. [soltar]: **después** de que la venta quedó guardada, borra la entrevista en curso del teléfono.
///    Se hace aparte porque el almacén de la entrevista no entra en la transacción de la base: si la
///    venta se revirtiera después de borrarla, se perdería la entrevista.
///
/// Si la venta no se completa (se sale de la pantalla, falla el guardado), no se llamó a nada que
/// cambie: la entrevista sigue en curso con sus horas y su nota (R44).
final class CerrarEntrevistaConVentaUseCase {
  CerrarEntrevistaConVentaUseCase(
    this._registrar,
    this._repository,
    this._destino, {
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final RegistrarResultadoVisitaUseCase _registrar;
  final EntrevistaEnCursoRepository _repository;
  final ResolverDestinoDeEntrevista _destino;
  final DateTime Function() _ahora;
  final AppLogger _log;

  Future<Either<Failure, VentaDeLaEntrevista>> preparar(FinalizarEntrevistaParams params) async {
    final invalida = HorasDeEntrevista.validar(
      entrada: params.entrada,
      salida: params.salida,
      ahora: _ahora(),
    );
    if (invalida != null) return Left(invalida);

    final espacioId = params.espacioId.trim();
    final espacioPersonaId = params.espacioPersonaId.trim();
    final campos = <String, String>{
      if (espacioId.isEmpty) 'espacio': 'Falta la casa de la entrevista',
      if (espacioPersonaId.isEmpty) 'persona': 'Elegí con quién fue la entrevista para seguir.',
    };
    if (campos.isNotEmpty) return Left(FailureValidacion(campos: campos));

    final DestinoDeEntrevista? destino;
    try {
      destino = await _destino.resolver(espacioId: espacioId, espacioPersonaId: espacioPersonaId);
    } on Object catch (e) {
      _log.error(
        LogModulo.agenda,
        'ENTREVISTA_DESTINO',
        'no se pudo leer dónde cuelga la venta de la entrevista',
        {'tipo': e.runtimeType.toString()},
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
    if (destino == null) return const Left(ventaSinLugar);
    final vinculo = destino.espacioPersonaId;
    if (vinculo == null || vinculo.trim().isEmpty) return const Left(ventaSinPersona);

    return Right(
      VentaDeLaEntrevista(
        espacioId: destino.espacioId,
        espacioPersonaId: vinculo,
        colportorId: params.colportorId.trim(),
        visita: RegistrarResultadoVisitaParams(
          ids: params.ids,
          espacioId: destino.espacioId,
          espacioPersonaId: vinculo,
          colportorId: params.colportorId,
          resultado: TipoResultadoVisita.venta,
          agendaId: params.agendaId,
          jornadaId: params.jornadaId,
          nota: params.nota,
        ),
      ),
    );
  }

  /// Guarda la visita `VENTA`. Se llama dentro de la transacción de la venta: si falla lanza
  /// [VisitaDeLaVentaNoGuardada] y la venta se revierte.
  Future<void> guardarVisita(VentaDeLaEntrevista venta) async {
    final guardada = await _registrar(venta.visita);
    guardada.fold((falla) => throw VisitaDeLaVentaNoGuardada(falla), (_) {});
  }

  /// Borra la entrevista en curso, una vez que la venta quedó guardada. Si el almacén falla devuelve
  /// la falla: la venta y la visita ya están, y la entrevista se puede cerrar después (mismos ids).
  Future<Either<Failure, Unit>> soltar(VentaDeLaEntrevista venta) async {
    try {
      await _repository.borrar(venta.colportorId, idVisita: venta.visitaId);
      return const Right(unit);
    } on Object catch (e) {
      _log.error(
        LogModulo.agenda,
        'ENTREVISTA_SOLTAR',
        'la venta se guardó pero no se pudo borrar la entrevista en curso',
        {'tipo': e.runtimeType.toString()},
      );
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }
}
