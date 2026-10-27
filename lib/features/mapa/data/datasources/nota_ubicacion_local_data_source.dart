import '../../domain/entities/nota_ubicacion.dart';

/// Persistencia local de las notas de un lugar (vista 39, C·05), sobre la tabla `nota` de la DB cifrada
/// (`target_type = UBICACION`). La implementa `NotaUbicacionLocalDataSourceDrift`.
///
/// **local-only — PII**: ninguna operación se encola al sync, y el texto no va a los logs. Cada
/// operación es una transacción. Los rechazos salen como `NotaRechazadaException`
/// (`nota_persona_local_data_source.dart`), que el repositorio traduce a un `Failure`.
abstract interface class NotaUbicacionLocalDataSource {
  /// Guarda [nota]. Si ya hay una con ese `id`, no escribe nada y devuelve la que estaba. El lugar
  /// tiene que existir y no estar dado de baja: si no, lanza `NotaRechazadaException`.
  Future<NotaUbicacion> agregar(NotaUbicacion nota);

  /// Cambia el texto y `updated_at` de la nota [id] (`created_at` y `created_by` no cambian). Si el
  /// texto ya es ese, no escribe nada. Lanza `NotaRechazadaException` si la nota no está, está borrada
  /// o su lugar está dado de baja.
  Future<NotaUbicacion> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  });

  /// Marca la nota [id] como borrada (idempotente).
  Future<NotaUbicacion> borrar({required String id, required DateTime ahora});

  /// Quita la marca de borrada de la nota [id] (idempotente).
  Future<NotaUbicacion> restaurar({required String id, required DateTime ahora});

  /// Las notas de [ubicacionId], activas y borradas, de la más nueva a la más vieja.
  Stream<List<NotaUbicacion>> observar(String ubicacionId);
}
