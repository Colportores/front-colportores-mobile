import '../../domain/entities/contexto_edicion_persona.dart';
import '../../domain/entities/espacio_persona.dart';
import '../../domain/entities/motivo_rechazo_persona.dart';
import '../../domain/entities/nota_persona.dart';
import '../../domain/entities/persona.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../../domain/repositories/persona_repository.dart' show ResultadoModificarPersona;

/// Resultado de [PersonaLocalDataSource.registrar]: la persona guardada y si ya estaba.
typedef RegistroPersona = ({Persona persona, bool yaEstaba});

/// Persistencia local de las personas de un espacio (HU-UBI-008), sobre las tablas `persona`,
/// `espacio_persona` y `nota` de la DB cifrada. La implementa `PersonaLocalDataSourceDrift`.
///
/// **local-only**: la persona y la nota no se encolan. Solo el vínculo `espacio_persona` entra al
/// sync (ADR-017), con ids, dentro de la misma transacción que la escritura (contrato-sync-engine §3).
abstract interface class PersonaLocalDataSource {
  /// Guarda [persona], [vinculo] y [nota] en **una** transacción, y encola el `insert` del vínculo. Si
  /// el encolado falla, no queda nada.
  ///
  /// - Si ya hay una persona con ese `id`, no escribe nada y la devuelve con `yaEstaba: true`.
  /// - El espacio del vínculo tiene que existir y estar activo, y su ubicación también: si no, lanza
  ///   [PersonaRechazadaException].
  Future<RegistroPersona> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  });

  /// Las personas activas de [espacioId] (persona y vínculo sin baja), de la más vieja a la más nueva.
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId);

  /// La persona [personaId] con su espacio vigente y, si está en solo lectura, por qué. `null` si no
  /// está en el teléfono.
  Future<ContextoEdicionPersona?> leerParaEditar(String personaId);

  /// Cambia el nombre, el apellido y el teléfono de [personaId] en **una** transacción, y deja el
  /// evento `persona_modificada` en el `audit_log` local. No encola nada: la persona es local-only. Si
  /// no cambia nada, no escribe. Lanza [PersonaRechazadaException] si la persona no está o está en
  /// solo lectura.
  Future<ResultadoModificarPersona> modificar({
    required String personaId,
    required String nombre,
    required String apellido,
    required String? telefono,
    required DateTime ahora,
  });
}

/// La persistencia rechazó la operación por [motivo]; el repositorio la traduce a un `Failure`.
final class PersonaRechazadaException implements Exception {
  const PersonaRechazadaException(this.motivo);

  final MotivoRechazoPersona motivo;

  @override
  String toString() => 'PersonaRechazadaException(${motivo.name})';
}
