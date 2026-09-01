import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../error/failure.dart';

/// Contrato de todo caso de uso (ADR-009).
///
/// - Vive en `domain`, es Dart puro: no conoce Riverpod, Drift, Supabase ni widgets.
/// - Recibe un objeto de parámetros [P] (o [NoParams]) y devuelve `Either<Failure, T>`.
/// - Se invoca como función: `await iniciarSesion(params)`.
abstract interface class UseCase<T, P> {
  Future<Either<Failure, T>> call(P params);
}

/// Caso de uso que expone un flujo reactivo (p. ej. un `watch` de Drift).
abstract interface class StreamUseCase<T, P> {
  Stream<T> call(P params);
}

/// Marcador para casos de uso sin parámetros.
final class NoParams extends Equatable {
  const NoParams();

  @override
  List<Object?> get props => const [];
}
