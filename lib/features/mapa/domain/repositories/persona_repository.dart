import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/contexto_edicion_persona.dart';
import '../entities/espacio_persona.dart';
import '../entities/nota_persona.dart';
import '../entities/persona.dart';
import '../entities/persona_del_espacio.dart';

/// Lo que devuelve [PersonaRepository.modificar]: la persona como quedó y si hubo algo que escribir
/// (`false` si lo que se pidió ya era lo que estaba).
typedef ResultadoModificarPersona = ({Persona persona, bool huboCambios});

/// Persistencia de las personas de un espacio (HU-UBI-008, ADR-001).
///
/// **local-only**: la persona y su nota no se encolan al sync. Lo único que sube es el vínculo
/// `espacio_persona`, solo con IDs (ADR-017), y se encola dentro de la misma transacción que la
/// escritura (contrato-sync-engine §3). Nunca devuelve ni registra un dato personal en un `Failure`.
abstract interface class PersonaRepository {
  /// Guarda [persona], su [vinculo] con el espacio y la [nota] opcional, **todo o nada**. Si ya hay
  /// una persona con ese `id`, no escribe nada y devuelve la que estaba (idempotente ante doble toque).
  ///
  /// El espacio tiene que existir y estar activo, y su ubicación también: si no, `FailureValidacion`
  /// con el campo `espacio`.
  Future<Either<Failure, Persona>> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  });

  /// Las personas activas de [espacioId], de la más vieja a la más nueva, que se actualiza sola
  /// cuando se agrega o se da de baja una. Un error de lectura sale por el `Stream`.
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId);

  /// La persona [personaId] con lo que hace falta para editarla (HU-UBI-010): cómo está hoy y si se
  /// la puede cambiar. `null` si ya no está en el teléfono.
  Future<Either<Failure, ContextoEdicionPersona?>> leerParaEditar(String personaId);

  /// Cambia el nombre, el apellido y el teléfono de [personaId] (HU-UBI-010), **todo o nada**, y deja
  /// una fila `persona_modificada` en el `audit_log` local con solo el id (nunca los valores). Los
  /// textos llegan ya limpios; [telefono] `null` es «sin teléfono». `updated_at` pasa a [ahora] (nunca
  /// hacia atrás) y `sync_version` no se toca: la persona es local-only, no se encola nada.
  ///
  /// Si no cambia nada, no escribe nada (ni `updated_at` ni auditoría) y devuelve `huboCambios: false`.
  /// Si la persona no está o está en solo lectura (de baja, o sin un espacio activo),
  /// `FailureValidacion` con el campo `persona`.
  Future<Either<Failure, ResultadoModificarPersona>> modificar({
    required String personaId,
    required String nombre,
    required String apellido,
    required String? telefono,
    required DateTime ahora,
  });
}
