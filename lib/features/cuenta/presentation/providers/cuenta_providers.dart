import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../cobranzas/presentation/providers/cobranzas_providers.dart';
import '../../data/datasources/detalle_de_mi_plata_local_data_source_drift.dart';
import '../../data/datasources/resumen_de_cuenta_local_data_source_drift.dart';
import '../../data/repositories/detalle_de_mi_plata_repository_impl.dart';
import '../../data/repositories/resumen_de_cuenta_repository_impl.dart';
import '../../domain/entities/detalle_de_mi_plata.dart';
import '../../domain/entities/resumen_de_cuenta.dart';
import '../../domain/repositories/detalle_de_mi_plata_repository.dart';
import '../../domain/repositories/resumen_de_cuenta_repository.dart';

// Cableado de Mi Cuenta (HU-CTA-001) y de Mi plata (HU-CTA-003). Presentation conoce domain; data se inyecta acá.

/// El reloj de Mi Cuenta («hace una semana» se cuenta desde acá); un test lo reemplaza.
final relojCuentaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// De dónde sale el resumen: las tablas `venta`, `cobranza` y `devolucion` de la DB local. Sin DB
/// abierta, su `Stream` falla con `FailureCuentaNoDisponible`.
final resumenDeCuentaRepositoryProvider = Provider<ResumenDeCuentaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return const ResumenDeCuentaSinBase();
  return ResumenDeCuentaRepositoryImpl(
    ResumenDeCuentaLocalDataSourceDrift(
      db,
      cobranzas: ref.watch(cobranzaLocalProvider),
      ahora: ref.watch(relojCuentaProvider),
    ),
  );
});

/// Sin reintentos: un `Stream` que falla (la base no se pudo leer) deja el error a la vista con su
/// «Reintentar» en vez de quedarse en «cargando» (Riverpod 3 reintenta 10 veces).
Duration? _sinReintentos(int intento, Object error) => null;

/// El resumen de Mi Cuenta del colportor, al día solo después de cada cobro, venta o devolución.
final resumenDeCuentaProvider = StreamProvider.autoDispose.family<ResumenDeCuenta, String>(
  (ref, colportorId) => ref.watch(resumenDeCuentaRepositoryProvider).observar(colportorId),
  retry: _sinReintentos,
);

/// De dónde sale el detalle de Mi plata: las mismas tablas locales que el resumen, más `persona`. Sin
/// DB abierta, su `Stream` falla con `FailureCuentaNoDisponible`.
final detalleDeMiPlataRepositoryProvider = Provider<DetalleDeMiPlataRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return const DetalleDeMiPlataSinBase();
  return DetalleDeMiPlataRepositoryImpl(
    DetalleDeMiPlataLocalDataSourceDrift(db, cobranzas: ref.watch(cobranzaLocalProvider)),
  );
});

/// El detalle de Mi plata del colportor, al día solo después de cada cobro, venta o devolución.
final detalleDeMiPlataProvider = StreamProvider.autoDispose.family<DetalleDeMiPlata, String>(
  (ref, colportorId) => ref.watch(detalleDeMiPlataRepositoryProvider).observar(colportorId),
  retry: _sinReintentos,
);
