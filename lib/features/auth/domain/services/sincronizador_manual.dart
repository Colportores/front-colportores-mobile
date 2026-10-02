import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';

/// "Sincronizar ahora" (HU-SYNC-007): le pide al motor de sync (`engine.syncNow()`, contrato en
/// docs-organizacion `contrato-sync-engine.md`) que suba lo pendiente y espera a que termine.
///
/// `Right` es que la corrida terminó (puede haber quedado algo sin subir: el que llama vuelve a
/// contar). `Left` es que no se pudo correr (sin conexión, sin sesión, motor no disponible).
abstract interface class SincronizadorManual {
  Future<Either<Failure, Unit>> sincronizarAhora();
}
