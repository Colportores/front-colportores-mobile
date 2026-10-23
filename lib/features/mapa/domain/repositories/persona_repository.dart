import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/espacio_persona.dart';
import '../entities/nota_persona.dart';
import '../entities/persona.dart';
import '../entities/persona_del_espacio.dart';

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
}
