import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/deposito.dart';
import '../entities/totales_de_depositos.dart';

/// Persistencia de los depósitos de efectivo del colportor (BACK-HU-CTA-004, #442).
///
/// Cada escritura es **todo o nada**, en una transacción local: el depósito y su encolado para el
/// sync, que sube sin dato de ninguna persona.
abstract interface class DepositoRepository {
  /// Guarda [deposito] y lo encola para el sync.
  ///
  /// - Si ya hay un depósito con ese `id`, no escribe nada y devuelve el que estaba (idempotente ante
  ///   un doble toque o un reintento).
  /// - Un ticket que ya respalda otro depósito vivo es [FailureDepositoTicketYaUsado]; cualquier otra
  ///   falla, [FailureDepositoNoGuardado].
  Future<Either<Failure, DepositoRegistrado>> registrar(Deposito deposito);

  /// Los depósitos vivos del teléfono, el más reciente primero, cada uno con su [Deposito.estado].
  Future<Either<Failure, List<Deposito>>> todos();

  /// Lo mismo que [todos], pero al día solo: emite al suscribirse y de nuevo cuando se registra un
  /// depósito o baja del servidor su validación o su rechazo (Mi plata y el retiro rechazado, #596).
  /// Si la base no se puede leer, falla con [FailureDepositoNoDisponible] y nunca emite una lista vacía:
  /// «no pude leer» no es «no depositaste nada».
  Stream<List<Deposito>> observar();

  /// Lo validado y lo «por validar», por separado (decisión «Acredita V1»); lo rechazado no suma a
  /// ninguno.
  Future<Either<Failure, TotalesDeDepositos>> totales();
}
