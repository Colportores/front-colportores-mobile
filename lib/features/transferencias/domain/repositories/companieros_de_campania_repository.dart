import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/companiero_de_campania.dart';

/// Los colportores de la campaña del colportor (vista 40, 40A·02: «¿A quién le pedís?»).
///
/// Es el único dato de la vista que **no** está en el teléfono: un colportor no lee a los demás
/// (la RLS de `usuario` y de `campania_colportor` lo impide) y la transferencia solo trae ids. Lo da el
/// servidor; sin él la pantalla dice que no pudo traerlos.
abstract interface class CompanierosDeCampaniaRepository {
  /// Los compañeros de [colportorId] en su campaña en curso, o [FailureCompanierosNoDisponibles].
  Future<Either<Failure, CompanierosDeCampania>> listar(String colportorId);
}
