import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/contexto_notas_persona.dart';
import '../entities/nota_persona.dart';

/// Persistencia de las notas de una persona (HU-UBI-012).
///
/// **local-only — PII**: las notas no se encolan al sync ni salen del teléfono. Nunca devuelve ni
/// registra el texto de una nota en un `Failure`.
abstract interface class NotaPersonaRepository {
  /// Guarda [nota]. Si ya hay una nota con ese `id`, no escribe nada y devuelve la que estaba
  /// (idempotente ante doble toque y reintento).
  ///
  /// La persona tiene que existir y estar en modo escritura: si no, `FailureValidacion` con el campo
  /// `persona`.
  Future<Either<Failure, NotaPersona>> agregar(NotaPersona nota);

  /// Cambia el texto de la nota [id] a [texto] y su `updated_at` a [ahora]; `created_at` y
  /// `created_by` no cambian. Una nota borrada no se edita (campo `nota`).
  Future<Either<Failure, NotaPersona>> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  });

  /// Marca la nota [id] como borrada (`deleted_at`); no se pierde nada. Idempotente.
  Future<Either<Failure, NotaPersona>> borrar({required String id, required DateTime ahora});

  /// Deshace [borrar]. Idempotente.
  Future<Either<Failure, NotaPersona>> restaurar({required String id, required DateTime ahora});

  /// Todas las notas de [personaId], activas y borradas, de la más nueva a la más vieja; se actualiza
  /// sola. Un error de lectura sale por el `Stream`.
  Stream<List<NotaPersona>> observar(String personaId);

  /// El nombre de la persona y si sus notas se pueden cambiar, o `null` si la persona no está.
  Future<Either<Failure, ContextoNotasPersona?>> leerContexto(String personaId);
}
