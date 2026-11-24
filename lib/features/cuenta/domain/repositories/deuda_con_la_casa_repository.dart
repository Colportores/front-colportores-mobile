import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/deuda_con_la_casa.dart';

/// La deuda del colportor con la casa editora (HU-CTA-002, vista 33B).
///
/// La deuda **baja con la sincronización** y el teléfono la calcula con lo que bajó (decisión de
/// Cristian, 05/11, «nada de consultas a cada rato»; backend-supabase 0179, #254): leerla no llama al
/// servidor, así que se ve igual con y sin señal, con la hora de la última sincronización.
abstract interface class DeudaConLaCasaRepository {
  /// La deuda de [colportorId] calculada con lo último que bajó, con la hora de esa bajada.
  ///
  /// `Right(null)`: el teléfono todavía no sincronizó nunca, así que no sabe nada de la deuda (no es
  /// «no debe nada»). [FailureDeudaNoDisponible]: no se pudo leer la base local. Nunca lanza.
  Future<Either<Failure, LecturaDeLaDeuda?>> leer(String colportorId);

  /// Avisa cada vez que cambia algo de lo que cuenta la deuda (la sincronización trajo cuenta, pedidos,
  /// depósitos, tickets o productos), para volver a leerla.
  Stream<void> get cambios;
}
