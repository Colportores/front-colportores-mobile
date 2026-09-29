import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/duplicado_ubicacion.dart';

/// Lo que el colportor decidió sobre los pares del scan de duplicados (HU-UBI-006: "conservar
/// histórico de ignorados 30 días"). Solo local: no entra al sync.
abstract interface class ParesDuplicadosRepository {
  /// Cuándo se decidió cada par, por `ParDuplicado.clave`. Incluye las decisiones vencidas: la
  /// ventana la aplica el caso de uso.
  Future<Either<Failure, Map<String, DateTime>>> decididos();

  /// Guarda [decision] sobre [par] con fecha [ahora]. Si el par ya tenía una, la reemplaza.
  Future<Either<Failure, Unit>> decidir(
    ParDuplicado par,
    DecisionParDuplicado decision, {
    required DateTime ahora,
  });
}
