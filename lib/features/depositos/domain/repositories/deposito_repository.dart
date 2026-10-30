import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/deposito.dart';

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

  /// Los depósitos vivos del teléfono, el más reciente primero.
  Future<Either<Failure, List<Deposito>>> todos();
}
