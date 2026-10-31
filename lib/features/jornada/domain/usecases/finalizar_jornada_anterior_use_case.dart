import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/jornada.dart';
import '../jornada_sin_cerrar.dart';
import '../repositories/jornada_repository.dart';
import '../repositories/jornadas_abiertas_repository.dart';
import '../services/disparador_backup.dart';

/// Parámetros de [FinalizarJornadaAnteriorUseCase].
final class FinalizarJornadaAnteriorParams extends Equatable {
  const FinalizarJornadaAnteriorParams({
    required this.colportorId,
    required this.jornadaId,
    required this.hora,
  });

  final String colportorId;

  /// La jornada abierta que tiene otra después y se cierra.
  final String jornadaId;

  /// La hora de fin que eligió la persona. Siempre hay una: nunca se inventa un fin.
  final DateTime hora;

  @override
  List<Object?> get props => [colportorId, jornadaId, hora];
}

/// HU-JOR-002, «Jornada que quedó abierta», para una jornada que **tiene otra después** (la que
/// quedó abierta de una recuperación de dispositivo, vista 34): la cierra con la [hora] que eligió la
/// persona, y solo con esa.
///
/// A diferencia de `FinalizarJornadaUseCase` —que cierra la jornada en curso, la más reciente—, acá
/// el fin tiene que estar después del inicio y no pasar del menor entre 12 h después del inicio,
/// ahora y el inicio de la jornada siguiente, porque el fin no pisa a la que sigue (las horas no se
/// cuentan dos veces). Las mismas reglas y los mismos errores que la corrección de Hoy
/// ([JornadaSinCerrar]):
/// - la jornada ya no está abierta, o ya no tiene otra después: `Left(FailureSinJornadaActiva)`
///   (no hay nada que corregir acá);
/// - no queda ningún minuto válido: `Left(FailureJornadaDeDiaAnterior)` con la siguiente actual;
/// - la hora cae fuera del rango: `Left(FailureHoraFueraDeRango)` con el rango real.
final class FinalizarJornadaAnteriorUseCase
    implements UseCase<Jornada, FinalizarJornadaAnteriorParams> {
  FinalizarJornadaAnteriorUseCase(
    this._abiertas,
    this._jornadas,
    this._backup, {
    DateTime Function()? ahora,
    this._alFallarBackup,
  }) : _ahora = ahora ?? DateTime.now;

  static const _relojAtrasado = FailureValidacion(
    campos: {'hora': 'La hora del teléfono es anterior al inicio de la jornada'},
    mensaje: JornadaSinCerrar.avisoRelojAtrasado,
  );

  final JornadasAbiertasRepository _abiertas;
  final JornadaRepository _jornadas;
  final DisparadorBackup _backup;
  final DateTime Function() _ahora;
  final void Function(Object error, StackTrace rastro)? _alFallarBackup;

  @override
  Future<Either<Failure, Jornada>> call(FinalizarJornadaAnteriorParams params) async {
    final ahora = _alMilisegundo(_ahora());
    final colportorId = params.colportorId.trim();
    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'colportorId': 'No hay un colportor para finalizar la jornada'}),
      );
    }

    final lectura = await _abiertas.abiertas(colportorId);
    final falla = lectura.fold<Failure?>((failure) => failure, (_) => null);
    if (falla != null) return Left(falla);
    final abiertas = lectura.fold<List<Jornada>>((_) => const [], (jornadas) => jornadas);
    final abierta = abiertas.where((j) => j.id == params.jornadaId).firstOrNull;
    if (abierta == null) return const Left(FailureSinJornadaActiva());

    final siguiente = await _jornadas.siguienteA(abierta);
    final fallaDeLaConsulta = siguiente.fold<Failure?>((failure) => failure, (_) => null);
    if (fallaDeLaConsulta != null) return Left(fallaDeLaConsulta);
    final inicioSiguiente = siguiente.fold<DateTime?>((_) => null, (j) => j?.inicio);
    // Ya no tiene otra después (la siguiente se dio de baja): es la jornada en curso y la cierra
    // Hoy, con sus reglas.
    if (inicioSiguiente == null) return const Left(FailureSinJornadaActiva());

    final tope = JornadaSinCerrar.topeDelFin(
      inicio: abierta.inicio,
      ahora: ahora,
      inicioSiguiente: inicioSiguiente,
    );
    final primerMinuto = JornadaSinCerrar.primerMinutoDelFin(abierta.inicio);
    if (tope.isBefore(primerMinuto)) {
      return Left(
        FailureJornadaDeDiaAnterior(inicio: abierta.inicio, inicioSiguiente: inicioSiguiente),
      );
    }
    final hora = _alMilisegundo(params.hora);
    if (!hora.isAfter(abierta.inicio) || hora.isAfter(tope)) {
      return Left(FailureHoraFueraDeRango(desde: primerMinuto, hasta: tope));
    }
    if (ahora.isBefore(abierta.inicio)) return const Left(_relojAtrasado);

    final resultado = await _jornadas.finalizar(
      abierta.finalizada(fin: hora, actualizadaEn: ahora),
    );
    if (resultado.isRight()) unawaited(_pedirBackup(colportorId));
    return resultado;
  }

  Future<void> _pedirBackup(String colportorId) async {
    try {
      await _backup.solicitar(colportorId);
    } on Object catch (e, rastro) {
      _alFallarBackup?.call(e, rastro);
    }
  }

  static DateTime _alMilisegundo(DateTime fecha) =>
      DateTime.fromMillisecondsSinceEpoch(fecha.millisecondsSinceEpoch, isUtc: true);
}
