import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../auth/domain/entities/campania_colportor.dart';

/// Puerto: las inscripciones del colportor (`campania_colportor`). Cómo llegan al teléfono sigue
/// abierto (coordinadores#20), así que todavía no hay implementación de producción.
abstract interface class InscripcionesColportor {
  /// Las inscripciones **vigentes hoy** de [usuarioId]: sin baja, de una campaña vigente
  /// (`campanias_vigentes_de()` de backend-supabase 0005). Cada una con su zona, o sin zona.
  Future<Either<Failure, List<CampaniaColportor>>> vigentesDe(String usuarioId);
}
