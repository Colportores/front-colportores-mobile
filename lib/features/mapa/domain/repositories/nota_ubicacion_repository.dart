import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/nota_ubicacion.dart';

/// Persistencia de las notas de un lugar (vista 39, C·05; decisión de Cristian, 23/10, «Notas casa»).
///
/// **local-only — PII**: las notas no se encolan al sync ni salen del teléfono. Nunca devuelve ni
/// registra el texto de una nota en un `Failure`.
abstract interface class NotaUbicacionRepository {
  /// Guarda [nota]. Si ya hay una nota con ese `id`, no escribe nada y devuelve la que estaba
  /// (idempotente ante doble toque y reintento).
  ///
  /// El lugar tiene que existir y no estar dado de baja: si no, `FailureValidacion` con el campo
  /// `ubicacion`.
  Future<Either<Failure, NotaUbicacion>> agregar(NotaUbicacion nota);

  /// Cambia el texto de la nota [id] a [texto] y su `updated_at` a [ahora]; `created_at` y
  /// `created_by` no cambian. Una nota borrada no se edita (campo `nota`).
  Future<Either<Failure, NotaUbicacion>> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  });

  /// Marca la nota [id] como borrada (`deleted_at`); no se pierde nada. Idempotente.
  Future<Either<Failure, NotaUbicacion>> borrar({required String id, required DateTime ahora});

  /// Deshace [borrar]. Idempotente.
  Future<Either<Failure, NotaUbicacion>> restaurar({required String id, required DateTime ahora});

  /// Todas las notas de [ubicacionId], activas y borradas, de la más nueva a la más vieja; se
  /// actualiza sola. Un error de lectura sale por el `Stream`.
  Stream<List<NotaUbicacion>> observar(String ubicacionId);
}
