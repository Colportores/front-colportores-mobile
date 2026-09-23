import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/jornada.dart';
import '../repositories/jornada_repository.dart';

/// Parámetros de [IniciarJornadaUseCase].
final class IniciarJornadaParams extends Equatable {
  const IniciarJornadaParams({required this.colportorId});

  /// UUID del usuario con la sesión iniciada; la capa de presentación lo toma de la sesión.
  final String colportorId;

  @override
  List<Object?> get props => [colportorId];
}

/// HU-JOR-001 — Iniciar jornada de trabajo.
///
/// 1. Si el colportor ya tiene una jornada en curso devuelve `Left(FailureJornadaActiva)` ("solo
///    una jornada activa a la vez"). El repositorio vuelve a garantizarlo al escribir, para el
///    caso de dos inicios casi simultáneos (ver [JornadaRepository.crear]).
/// 2. Si no, crea la jornada con `inicio = now()` en UTC, `id` UUID v7 generado localmente
///    (esquema-datos.md §Principios 2) y la auditoría con el colportor como `created_by`.
///
/// El `id` y el reloj se inyectan: el dominio no depende del paquete `uuid` y los tests fijan la
/// hora sin esperar.
///
/// TODO(#70): la HU dice "`hora_inicio = now()` por defecto, editable ±30 minutos", pero no dice
/// qué pasa con una hora fuera de ese rango (rechazarla o recortarla al borde). Hasta que se
/// resuelva en el issue, el caso de uso solo inicia con la hora actual.
final class IniciarJornadaUseCase implements UseCase<Jornada, IniciarJornadaParams> {
  /// [_generarId] se pasa como `generarId:` (parámetro nombrado privado, Dart ≥ 3.10).
  IniciarJornadaUseCase(this._repository, {required this._generarId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final JornadaRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Jornada>> call(IniciarJornadaParams params) async {
    // La hora del toque, no la de después de consultar la DB.
    final inicio = _ahora().toUtc();
    final colportorId = params.colportorId.trim();

    if (colportorId.isEmpty) {
      return const Left(
        FailureValidacion(campos: {'colportorId': 'No hay un colportor para iniciar la jornada'}),
      );
    }

    final activa = await _repository.obtenerActiva(colportorId);
    return activa.fold<Future<Either<Failure, Jornada>>>((failure) async => Left(failure), (
      abierta,
    ) async {
      if (abierta != null) return const Left(FailureJornadaActiva());

      final jornada = Jornada(
        id: _generarId(),
        colportorId: colportorId,
        inicio: inicio,
        auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: colportorId),
      );
      return _repository.crear(jornada);
    });
  }
}
