import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../auth/domain/entities/campania_colportor.dart';

/// Puerto: las inscripciones del colportor (`campania_colportor`). Cómo llegan al teléfono sigue
/// abierto (coordinadores#20), así que todavía no hay implementación de producción.
abstract interface class InscripcionesColportor {
  /// Las inscripciones **vigentes hoy** de [usuarioId]: sin baja, de una campaña vigente
  /// (`campanias_vigentes_de()` de backend-supabase 0005). Cada una con su zona, o sin zona.
  ///
  /// «Hoy» tiene que ser la **misma fecha base** que el `current_date` del servidor
  /// (`campania_vigente()`: `fecha_inicio <= current_date` y `fecha_fin >= current_date`), no la
  /// fecha local del teléfono sin más. Si no, en el primer y el último día de una campaña, cerca
  /// de la medianoche, la app y el servidor toman campañas distintas y eligen otra zona.
  Future<Either<Failure, List<CampaniaColportor>>> vigentesDe(String usuarioId);
}
