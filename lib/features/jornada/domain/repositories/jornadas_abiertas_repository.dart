import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/jornada.dart';

/// Las jornadas abiertas de un colportor, todas (HU-JOR-002, «Jornada que quedó abierta»).
///
/// Aparte de `JornadaRepository`, que ve una sola: la jornada en curso. Después de recuperar los
/// datos de otro teléfono (vista 34) puede haber más de una abierta.
abstract interface class JornadasAbiertasRepository {
  /// Las jornadas abiertas de [colportorId] (sin `fin` y sin soft delete), la de `inicio` más viejo
  /// primero.
  Future<Either<Failure, List<Jornada>>> abiertas(String colportorId);
}
