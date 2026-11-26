import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/companiero_de_campania.dart';
import '../../domain/repositories/companieros_de_campania_repository.dart';

/// La fuente de los compañeros de campaña que usa la app **hasta que el servidor la dé** (como
/// `EstadoCuentaSinFuente` antes de backend#164).
///
/// Un colportor no puede leer a los demás: la RLS de `usuario` y de `campania_colportor` solo le deja ver
/// lo propio, y no hay una RPC que devuelva «los colportores de mi campaña» (la del panel,
/// HU-CAM-004, es del coordinador). Hasta que exista, la pantalla «Pedir transferencia» dice que no pudo
/// traerlos en vez de inventar una lista: ver «Cristian §3» en los pendientes de #512. `main.dart` la
/// reemplaza cuando haya una fuente real.
final class CompanierosDeCampaniaSinFuente implements CompanierosDeCampaniaRepository {
  const CompanierosDeCampaniaSinFuente();

  @override
  Future<Either<Failure, CompanierosDeCampania>> listar(String colportorId) async =>
      const Left(FailureCompanierosNoDisponibles());
}
