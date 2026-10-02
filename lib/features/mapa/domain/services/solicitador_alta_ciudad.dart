import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../value_objects/coordenadas.dart';

/// Puerto: pedirle al administrador que dé de alta la ciudad de [punto] (HU-UBI-001, «Solicitar
/// alta de ciudad al administrador»).
///
/// Es una escritura contra el servidor: no hay endpoint hasta que el BFF exista
/// (docs-organizacion#22), así que la solicitud real queda pendiente y el puerto puede fallar con
/// [FailureSinConexion].
abstract interface class SolicitadorAltaCiudad {
  Future<Either<Failure, Unit>> solicitar({
    required String colportorId,
    required Coordenadas punto,
  });
}
