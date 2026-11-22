import '../../domain/entities/contexto_notas_persona.dart';
import '../../domain/entities/motivo_rechazo_nota.dart';
import '../../domain/entities/nota_persona.dart';

/// Persistencia local de las notas de una persona (HU-UBI-012), sobre la tabla `nota` de la DB cifrada
/// (`target_type = PERSONA`). La implementa `NotaPersonaLocalDataSourceDrift`.
///
/// **local-only — PII**: ninguna operación se encola al sync, y el texto no va a los logs. Cada
/// operación es una transacción.
abstract interface class NotaPersonaLocalDataSource {
  /// Guarda [nota]. Si ya hay una con ese `id`, no escribe nada y devuelve la que estaba. La persona
  /// tiene que existir y estar en modo escritura: si no, lanza [NotaRechazadaException].
  Future<NotaPersona> agregar(NotaPersona nota);

  /// Cambia el texto y `updated_at` de la nota [id] (`created_at` y `created_by` no cambian). Si el
  /// texto ya es ese, no escribe nada. Lanza [NotaRechazadaException] si la nota no está, está borrada
  /// o su persona está en solo lectura.
  Future<NotaPersona> editar({required String id, required String texto, required DateTime ahora});

  /// Marca la nota [id] como borrada (idempotente).
  Future<NotaPersona> borrar({required String id, required DateTime ahora});

  /// Quita la marca de borrada de la nota [id] (idempotente).
  Future<NotaPersona> restaurar({required String id, required DateTime ahora});

  /// Las notas de [personaId], activas y borradas, de la más nueva a la más vieja.
  Stream<List<NotaPersona>> observar(String personaId);

  /// El nombre de la persona y si sus notas son de solo lectura, o `null` si no está.
  Future<ContextoNotasPersona?> leerContexto(String personaId);
}

/// La persistencia rechazó la operación por [motivo]; el repositorio la traduce a un `Failure`.
final class NotaRechazadaException implements Exception {
  const NotaRechazadaException(this.motivo);

  final MotivoRechazoNota motivo;

  @override
  String toString() => 'NotaRechazadaException(${motivo.name})';
}
