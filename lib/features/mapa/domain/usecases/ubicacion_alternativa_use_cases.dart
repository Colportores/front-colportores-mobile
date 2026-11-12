import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/espacio_persona.dart';
import '../entities/estado_ubicacion_alternativa.dart';
import '../entities/ubicacion.dart';
import '../repositories/ubicacion_alternativa_repository.dart';

// Los casos de uso de la ubicación alternativa de cobranza (HU-UBI-013). Sin red se completan: el
// cambio queda en el teléfono y el vínculo sube cuando hay conexión (ADR-017).

/// Parámetros de [EstablecerUbicacionAlternativaUseCase].
final class EstablecerUbicacionAlternativaParams extends Equatable {
  const EstablecerUbicacionAlternativaParams({
    required this.personaId,
    required this.espacioId,
    required this.ubicacionId,
    required this.colportorId,
  });

  final String personaId;
  final String espacioId;

  /// La ubicación que se elige como alternativa.
  final String ubicacionId;

  /// Quién cobra: solo puede elegir ubicaciones que registró él.
  final String colportorId;

  @override
  List<Object?> get props => [personaId, espacioId, ubicacionId, colportorId];
}

/// Parámetros de [QuitarUbicacionAlternativaUseCase].
final class QuitarUbicacionAlternativaParams extends Equatable {
  const QuitarUbicacionAlternativaParams({required this.personaId, required this.espacioId});

  final String personaId;
  final String espacioId;

  @override
  List<Object?> get props => [personaId, espacioId];
}

/// HU-UBI-013 — «Establecer ubicación alternativa de cobranza».
///
/// 1. Valida que lleguen los cuatro ids (`FailureValidacion`, sin tocar la DB).
/// 2. Fija la alternativa en el repositorio (la fila y su encolado, una transacción). Cambiarla por
///    otra es lo mismo que fijarla; elegir la que ya estaba no escribe nada.
final class EstablecerUbicacionAlternativaUseCase
    implements UseCase<EspacioPersona, EstablecerUbicacionAlternativaParams> {
  EstablecerUbicacionAlternativaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final UbicacionAlternativaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, EspacioPersona>> call(EstablecerUbicacionAlternativaParams params) {
    final personaId = params.personaId.trim();
    final espacioId = params.espacioId.trim();
    final ubicacionId = params.ubicacionId.trim();
    final colportorId = params.colportorId.trim();
    final errores = <String, String>{
      if (personaId.isEmpty) 'persona': 'Falta la persona',
      if (espacioId.isEmpty) 'espacio': 'Falta el espacio',
      if (ubicacionId.isEmpty) 'ubicacionAlternativa': 'Elegí la ubicación alternativa',
      if (colportorId.isEmpty) 'colportor': 'Falta quién cobra',
    };
    if (errores.isNotEmpty) return Future.value(Left(FailureValidacion(campos: errores)));
    return _repository.establecer(
      personaId: personaId,
      espacioId: espacioId,
      ubicacionId: ubicacionId,
      colportorId: colportorId,
      ahora: _ahora(),
    );
  }
}

/// HU-UBI-013 — «Quitar ubicación alternativa»: la cobranza vuelve a la ubicación del espacio.
/// Idempotente; también quita una alternativa dada de baja.
final class QuitarUbicacionAlternativaUseCase
    implements UseCase<EspacioPersona, QuitarUbicacionAlternativaParams> {
  QuitarUbicacionAlternativaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final UbicacionAlternativaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, EspacioPersona>> call(QuitarUbicacionAlternativaParams params) {
    final personaId = params.personaId.trim();
    final espacioId = params.espacioId.trim();
    final errores = <String, String>{
      if (personaId.isEmpty) 'persona': 'Falta la persona',
      if (espacioId.isEmpty) 'espacio': 'Falta el espacio',
    };
    if (errores.isNotEmpty) return Future.value(Left(FailureValidacion(campos: errores)));
    return _repository.quitar(personaId: personaId, espacioId: espacioId, ahora: _ahora());
  }
}

/// Dónde se le cobra a una persona en un espacio, al día. Es lo que lee la ficha («Ubicación
/// alternativa dada de baja») y lo que HU-VIS-006 usa para sugerir el destino de la cobranza
/// (`EstadoUbicacionAlternativa.sugerida`: una alternativa de baja no se sugiere).
final class ObservarUbicacionAlternativaUseCase {
  const ObservarUbicacionAlternativaUseCase(this._repository);

  final UbicacionAlternativaRepository _repository;

  Stream<EstadoUbicacionAlternativa> call({required String personaId, required String espacioId}) =>
      _repository.observar(personaId: personaId, espacioId: espacioId);
}

/// Las ubicaciones entre las que se elige la alternativa de una persona de [espacioId]. Vacía:
/// «Registrá otra ubicación para usarla como alternativa».
final class ObservarCandidatasAlternativaUseCase {
  const ObservarCandidatasAlternativaUseCase(this._repository);

  final UbicacionAlternativaRepository _repository;

  Stream<List<Ubicacion>> call({required String colportorId, required String espacioId}) =>
      _repository.observarCandidatas(colportorId: colportorId, espacioId: espacioId);
}
