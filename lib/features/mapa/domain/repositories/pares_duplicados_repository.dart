import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/duplicado_ubicacion.dart';

/// Lo que el colportor decidió sobre los pares del scan de duplicados (HU-UBI-006: «Son distintos»
/// no vuelve nunca, «Ignorar» esconde el par 30 días). Solo local por ahora: la tabla del servidor
/// (`ubicacion_par_decidido`, migración 0032) existe, pero registrarla en el motor de sync es del
/// motor (#178).
abstract interface class ParesDuplicadosRepository {
  /// Lo decidido sobre cada par, por `ParDuplicado.clave`. Incluye las decisiones vencidas: si
  /// siguen escondiendo el par lo decide `ParDecidido.ocultaEn`.
  Future<Either<Failure, Map<String, ParDecidido>>> decididos();

  /// Lo mismo, reactivo: emite de nuevo cada vez que se decide un par. Un error de lectura sale
  /// como error del stream.
  Stream<Map<String, ParDecidido>> observarDecididos();

  /// Los pares cuya última unión el servidor rechazó y quedaron separados en el teléfono (HU-UBI-006,
  /// decisión de Cristian, 10/11, «Unión rech.»; #679), por `ParDuplicado.clave`, con el código del
  /// rechazo (`UB003`, `UB004`, `42501`, `CG001`…). Reactivo. Un error de lectura sale como error del
  /// stream.
  Stream<Map<String, String>> observarUnionesRechazadas();

  /// Guarda [decision] sobre [par] con fecha [ahora]. Si el par ya tenía una, la reemplaza.
  Future<Either<Failure, Unit>> decidir(
    ParDuplicado par,
    DecisionParDuplicado decision, {
    required DateTime ahora,
  });
}
