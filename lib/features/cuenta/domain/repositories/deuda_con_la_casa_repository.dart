import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/deuda_con_la_casa.dart';

/// La deuda del colportor con la casa editora (HU-CTA-002, vista 33B).
///
/// La cuenta la hace el servidor (RPC `mi_deuda_con_la_casa_editora`); el teléfono guarda la última
/// respuesta con su hora y la muestra sin conexión (decisión de Cristian, 03/11, «Leer deuda»).
abstract interface class DeudaConLaCasaRepository {
  /// La última respuesta guardada de [colportorId], o `null` si nunca llegó una. Nunca lanza: una
  /// base que no se puede leer es lo mismo que no tener nada guardado.
  Future<LecturaDeLaDeuda?> ultimaGuardada(String colportorId);

  /// Le pregunta al servidor, guarda la respuesta con la hora de ahora y la devuelve.
  ///
  /// Sin conexión: [FailureDeudaSinConexion]. Cualquier otra falla del servidor o una respuesta que
  /// no se entiende: [FailureDeudaNoDisponible]. En ambos casos lo guardado queda como estaba.
  Future<Either<Failure, LecturaDeLaDeuda>> leer(String colportorId);
}
