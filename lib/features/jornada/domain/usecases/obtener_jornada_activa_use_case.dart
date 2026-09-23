import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/jornada.dart';
import '../repositories/jornada_repository.dart';

/// Parámetros de [ObtenerJornadaActivaUseCase].
final class ObtenerJornadaActivaParams extends Equatable {
  const ObtenerJornadaActivaParams({required this.colportorId});

  /// UUID del usuario con la sesión iniciada.
  final String colportorId;

  @override
  List<Object?> get props => [colportorId];
}

/// La jornada en curso del colportor, o `null` si no tiene ninguna (HU-JOR-001).
///
/// Es lo que la pantalla principal lee al abrirse para saber si mostrar "Iniciar jornada" o
/// "Jornada activa". Si hubiera más de una abierta (después de un `recover()`), el repositorio
/// devuelve la más reciente; la regla de "jornada que quedó abierta" es de HU-JOR-002.
final class ObtenerJornadaActivaUseCase implements UseCase<Jornada?, ObtenerJornadaActivaParams> {
  ObtenerJornadaActivaUseCase(this._repository);

  final JornadaRepository _repository;

  @override
  Future<Either<Failure, Jornada?>> call(ObtenerJornadaActivaParams params) async {
    final colportorId = params.colportorId.trim();
    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'colportorId': 'No hay un colportor para leer la jornada'}),
      );
    }
    return _repository.obtenerActiva(colportorId);
  }
}
