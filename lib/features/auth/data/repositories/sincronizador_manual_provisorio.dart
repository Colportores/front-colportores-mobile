import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../domain/services/sincronizador_manual.dart';

/// Provisorio: el motor de sync todavía no está en la app (ADR-007, #178 / #182), así que
/// "Sincronizar ahora" no puede subir nada y lo dice. Se reemplaza por una llamada a
/// `engine.syncNow()` ([contrato](docs-organizacion `contrato-sync-engine.md`)) en la integración.
final class SincronizadorManualProvisorio implements SincronizadorManual {
  const SincronizadorManualProvisorio();

  @override
  Future<Either<Failure, Unit>> sincronizarAhora() async =>
      const Left(FailureSincronizacionNoDisponible());
}
