import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/nota_persona.dart';
import '../repositories/nota_persona_repository.dart';
import '../services/validador_nota.dart';

// Los casos de uso de las notas de una persona (HU-UBI-012). Todo es local: sin red se completan.

/// Parámetros de [AgregarNotaPersonaUseCase]. El [id] lo genera la pantalla **una vez por formulario**
/// y lo repite en cada intento: un doble toque o un «Reintentar» tras una falla no crean dos notas.
final class AgregarNotaPersonaParams extends Equatable {
  const AgregarNotaPersonaParams({
    required this.id,
    required this.personaId,
    required this.colportorId,
    required this.texto,
  });

  final String id;
  final String personaId;

  /// UUID del usuario con la sesión iniciada (`created_by`).
  final String colportorId;

  final String texto;

  /// Lleva el texto de una nota (PII): ver `NotaPersona.stringify`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [id, personaId, colportorId, texto];
}

/// Agrega una nota a una persona. Valida que el texto no esté vacío; el límite de 5000 caracteres es
/// blando (la pantalla advierte y deja guardar).
final class AgregarNotaPersonaUseCase implements UseCase<NotaPersona, AgregarNotaPersonaParams> {
  AgregarNotaPersonaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaPersonaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaPersona>> call(AgregarNotaPersonaParams params) {
    final problema = ValidadorNota.problema(params.texto);
    final campos = <String, String>{
      if (params.id.trim().isEmpty) 'id': 'Falta el identificador de la nota',
      if (params.personaId.trim().isEmpty) 'persona': 'Falta la persona de la nota',
      if (params.colportorId.trim().isEmpty) 'colportorId': 'No hay un colportor para la nota',
      if (problema != null) 'texto': ValidadorNota.mensaje(problema),
    };
    if (campos.isNotEmpty) return Future.value(Left(FailureValidacion(campos: campos)));

    final ahora = _ahora();
    return _repository.agregar(
      NotaPersona(
        id: params.id.trim(),
        personaId: params.personaId.trim(),
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

/// Parámetros de [EditarNotaPersonaUseCase].
final class EditarNotaPersonaParams extends Equatable {
  const EditarNotaPersonaParams({required this.notaId, required this.texto});

  final String notaId;
  final String texto;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [notaId, texto];
}

/// Cambia el texto de una nota propia: `updated_at` se actualiza; `created_at` y `created_by` se
/// conservan.
final class EditarNotaPersonaUseCase implements UseCase<NotaPersona, EditarNotaPersonaParams> {
  EditarNotaPersonaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaPersonaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaPersona>> call(EditarNotaPersonaParams params) {
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
final class BorrarNotaPersonaUseCase implements UseCase<NotaPersona, String> {
  BorrarNotaPersonaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaPersonaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaPersona>> call(String notaId) => notaId.trim().isEmpty
      ? Future.value(
          const Left(FailureValidacion(campos: {'id': 'Falta el identificador de la nota'})),
        )
      : _repository.borrar(id: notaId.trim(), ahora: _ahora());
}

/// Restaura una nota borrada («Deshacer» y «Restaurar»).
final class RestaurarNotaPersonaUseCase implements UseCase<NotaPersona, String> {
  RestaurarNotaPersonaUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final NotaPersonaRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, NotaPersona>> call(String notaId) => notaId.trim().isEmpty
      ? Future.value(
          const Left(FailureValidacion(campos: {'id': 'Falta el identificador de la nota'})),
        )
      : _repository.restaurar(id: notaId.trim(), ahora: _ahora());
}
