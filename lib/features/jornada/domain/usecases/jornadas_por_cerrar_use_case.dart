import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/jornada.dart';
import '../repositories/jornada_repository.dart';
import '../repositories/jornadas_abiertas_repository.dart';

/// Una jornada que quedó abierta y tiene otra después: hay que preguntar a qué hora terminó.
final class JornadaPorCerrar extends Equatable {
  const JornadaPorCerrar({required this.jornada, required this.inicioSiguiente});

  final Jornada jornada;

  /// Cuándo empezó la jornada que sigue (abierta o ya cerrada): el tope del fin de [jornada].
  final DateTime inicioSiguiente;

  @override
  List<Object?> get props => [jornada.id, inicioSiguiente];
}

/// Parámetros de [JornadasPorCerrarUseCase].
final class JornadasPorCerrarParams extends Equatable {
  const JornadasPorCerrarParams({required this.colportorId});

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  @override
  List<Object?> get props => [colportorId];
}

/// HU-JOR-002, «Jornada que quedó abierta»: las jornadas abiertas del colportor que tienen otra
/// después (abierta o cerrada), la más vieja primero. Pasa cuando una recuperación de dispositivo
/// (vista 34, `recover()`) trae dos jornadas abiertas del mismo día: la última es la jornada en
/// curso, de la que se ocupa Hoy; **cada una de las anteriores** pasa por «¿A qué hora terminaste?»
/// (vista 21, 21A) con el inicio de la siguiente como tope, porque cerrarla con la hora de ahora
/// contaría dos veces las mismas horas, y ninguna se cierra sola.
final class JornadasPorCerrarUseCase
    implements UseCase<List<JornadaPorCerrar>, JornadasPorCerrarParams> {
  JornadasPorCerrarUseCase(this._abiertas, this._jornadas);

  final JornadasAbiertasRepository _abiertas;
  final JornadaRepository _jornadas;

  @override
  Future<Either<Failure, List<JornadaPorCerrar>>> call(JornadasPorCerrarParams params) async {
    final colportorId = params.colportorId.trim();
    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'colportorId': 'No hay un colportor para leer la jornada'}),
      );
    }
    final lectura = await _abiertas.abiertas(colportorId);
    final falla = lectura.fold<Failure?>((failure) => failure, (_) => null);
    if (falla != null) return Left(falla);
    final abiertas = lectura.fold<List<Jornada>>((_) => const [], (jornadas) => jornadas);

    final porCerrar = <JornadaPorCerrar>[];
    for (final jornada in abiertas) {
      final siguiente = await _jornadas.siguienteA(jornada);
      final fallaDeLaSiguiente = siguiente.fold<Failure?>((failure) => failure, (_) => null);
      if (fallaDeLaSiguiente != null) return Left(fallaDeLaSiguiente);
      final inicio = siguiente.fold<DateTime?>((_) => null, (j) => j?.inicio);
      if (inicio != null) {
        porCerrar.add(JornadaPorCerrar(jornada: jornada, inicioSiguiente: inicio));
      }
    }
    return Right(porCerrar);
  }
}
