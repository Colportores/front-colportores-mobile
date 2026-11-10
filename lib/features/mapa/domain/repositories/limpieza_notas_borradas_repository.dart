import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';

/// La limpieza de las notas de persona y de lugar borradas hace más de 90 días (HU-UBI-012, `RetencionNotasBorradas`).
///
/// **local-only — PII**: nunca devuelve ni registra el texto de una nota.
abstract interface class LimpiezaNotasBorradasRepository {
  /// Borra para siempre las notas de persona y de lugar que se borraron hace más de 90 días contados hasta
  /// [ahora]. Las activas y las borradas más nuevas no se tocan. Devuelve cuántas borró.
  Future<Either<Failure, int>> purgarVencidas({required DateTime ahora});
}
