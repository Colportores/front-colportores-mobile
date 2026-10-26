import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/espacio_persona.dart';
import '../entities/estado_ubicacion_alternativa.dart';
import '../entities/ubicacion.dart';

/// Persistencia de la ubicación alternativa de cobranza de una persona (HU-UBI-013): la columna
/// `espacio_persona.ubicacion_cobranza_alt_id`, que sube con el vínculo solo con ids (ADR-017) y se
/// encola en la misma transacción que la escritura (contrato-sync-engine §3). Nunca devuelve ni
/// registra un dato personal en un `Failure`.
abstract interface class UbicacionAlternativaRepository {
  /// Dónde se le cobra a [personaId] en [espacioId], al día cuando se elige, se quita o se da de baja
  /// la alternativa. Un error de lectura sale por el `Stream`.
  Stream<EstadoUbicacionAlternativa> observar({
    required String personaId,
    required String espacioId,
  });

  /// Las ubicaciones que [colportorId] puede elegir como alternativa para una persona de [espacioId]:
  /// las activas que registró él, sin la ubicación del propio espacio. Vacía = «Registrá otra
  /// ubicación para usarla como alternativa». Un error de lectura sale por el `Stream`.
  Stream<List<Ubicacion>> observarCandidatas({
    required String colportorId,
    required String espacioId,
  });

  /// Fija [ubicacionId] como alternativa de [personaId] en [espacioId], **todo o nada** (la fila y su
  /// encolado). Cambiarla es lo mismo que fijarla de nuevo. Si ya era esa, no escribe nada y devuelve
  /// el vínculo tal cual (idempotente ante doble toque).
  ///
  /// `FailureValidacion` con el campo `persona`, `espacio` o `ubicacionAlternativa` si la persona o
  /// el espacio son de solo lectura, o si la ubicación no existe, no es de [colportorId], está de baja
  /// o es la del propio espacio.
  Future<Either<Failure, EspacioPersona>> establecer({
    required String personaId,
    required String espacioId,
    required String ubicacionId,
    required String colportorId,
    required DateTime ahora,
  });

  /// Quita la alternativa: la cobranza vuelve a la ubicación del espacio. Si no había, no escribe
  /// nada. Funciona aunque la alternativa esté dada de baja (es justo lo que hay que hacer entonces).
  /// Mismas condiciones sobre la persona y el espacio que [establecer].
  Future<Either<Failure, EspacioPersona>> quitar({
    required String personaId,
    required String espacioId,
    required DateTime ahora,
  });
}
