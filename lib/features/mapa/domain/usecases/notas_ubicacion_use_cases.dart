import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/nota_ubicacion.dart';
import '../repositories/nota_ubicacion_repository.dart';
import '../services/validador_nota.dart';

// Los casos de uso de las notas de un lugar (vista 39, C·05). Todo es local: sin red se completan.

/// Parámetros de [AgregarNotaUbicacionUseCase]. El [id] lo genera la pantalla **una vez por
/// formulario** y lo repite en cada intento: un doble toque o un «Reintentar» tras una falla no crean
/// dos notas.
final class AgregarNotaUbicacionParams extends Equatable {
  const AgregarNotaUbicacionParams({
    required this.id,
    required this.ubicacionId,
    required this.colportorId,
    required this.texto,
  });

  final String id;
  final String ubicacionId;

  /// UUID del usuario con la sesión iniciada (`created_by`).
  final String colportorId;

  final String texto;

  /// Lleva el texto de una nota (PII): ver `NotaUbicacion.stringify`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, ubicacionId, colportorId, texto];
}

/// Agrega una nota a un lugar. Valida que el texto no esté vacío; el límite de 5000 caracteres es
/// blando (la pantalla advierte y deja guardar), como en las notas de una persona.
final class AgregarNotaUbicacionUseCase
    implements UseCase<NotaUbicacion, AgregarNotaUbicacionParams> {
  AgregarNotaUbicacionUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaUbicacionRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaUbicacion>> call(AgregarNotaUbicacionParams params) {
    final problema = ValidadorNota.problema(params.texto);
    final campos = <String, String>{
      if (params.id.trim().isEmpty) 'id': 'Falta el identificador de la nota',
      if (params.ubicacionId.trim().isEmpty) 'ubicacion': 'Falta el lugar de la nota',
      if (params.colportorId.trim().isEmpty) 'colportorId': 'No hay un colportor para la nota',
      if (problema != null) 'texto': ValidadorNota.mensaje(problema),
    };
    if (campos.isNotEmpty) return Future.value(Left(FailureValidacion(campos: campos)));

    final ahora = _ahora();
    return _repository.agregar(
      NotaUbicacion(
        id: params.id.trim(),
        ubicacionId: params.ubicacionId.trim(),
        texto: ValidadorNota.limpiar(params.texto),
        auditoria: Auditoria(
          createdAt: ahora,
          updatedAt: ahora,
          createdBy: params.colportorId.trim(),
        ),
      ),
    );
  }
}

/// Parámetros de [EditarNotaUbicacionUseCase].
final class EditarNotaUbicacionParams extends Equatable {
  const EditarNotaUbicacionParams({required this.notaId, required this.texto});

  final String notaId;
  final String texto;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [notaId, texto];
}

/// Cambia el texto de una nota: `updated_at` se actualiza; `created_at` y `created_by` se conservan.
final class EditarNotaUbicacionUseCase
    implements UseCase<NotaUbicacion, EditarNotaUbicacionParams> {
  EditarNotaUbicacionUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaUbicacionRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaUbicacion>> call(EditarNotaUbicacionParams params) {
    final problema = ValidadorNota.problema(params.texto);
    final campos = <String, String>{
      if (params.notaId.trim().isEmpty) 'id': 'Falta el identificador de la nota',
      if (problema != null) 'texto': ValidadorNota.mensaje(problema),
    };
    if (campos.isNotEmpty) return Future.value(Left(FailureValidacion(campos: campos)));
    return _repository.editar(
      id: params.notaId.trim(),
      texto: ValidadorNota.limpiar(params.texto),
      ahora: _ahora(),
    );
  }
}

/// Borra una nota (soft delete: `deleted_at`). Se puede restaurar.
final class BorrarNotaUbicacionUseCase implements UseCase<NotaUbicacion, String> {
  BorrarNotaUbicacionUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaUbicacionRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaUbicacion>> call(String notaId) => notaId.trim().isEmpty
      ? Future.value(
          const Left(FailureValidacion(campos: {'id': 'Falta el identificador de la nota'})),
        )
      : _repository.borrar(id: notaId.trim(), ahora: _ahora());
}

/// Restaura una nota borrada («Deshacer» y «Restaurar»).
final class RestaurarNotaUbicacionUseCase implements UseCase<NotaUbicacion, String> {
  RestaurarNotaUbicacionUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaUbicacionRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaUbicacion>> call(String notaId) => notaId.trim().isEmpty
      ? Future.value(
          const Left(FailureValidacion(campos: {'id': 'Falta el identificador de la nota'})),
        )
      : _repository.restaurar(id: notaId.trim(), ahora: _ahora());
}
