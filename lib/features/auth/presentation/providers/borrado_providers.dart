import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../data/repositories/intentos_borrado_repository_impl.dart';
import '../../data/repositories/sincronizador_manual_provisorio.dart';
import '../../domain/repositories/intentos_borrado_repository.dart';
import '../../domain/services/sincronizador_manual.dart';
import '../../domain/usecases/sincronizar_ahora_use_case.dart';
import '../../domain/usecases/verificar_password_borrado_use_case.dart';
import 'db_local_providers.dart';

// Cableado de la confirmación final del borrado de datos locales (HU-AUTH-010, vista 19).

/// Reloj de la espera de intentos (inyectable en tests).
final relojBorradoProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final intentosBorradoRepositoryProvider = Provider<IntentosBorradoRepository>(
  (ref) => IntentosBorradoRepositoryImpl(ref.watch(almacenSeguroProvider)),
);

final verificarPasswordBorradoUseCaseProvider = Provider<VerificarPasswordBorradoUseCase>(
  (ref) => VerificarPasswordBorradoUseCase(
    ref.watch(dbLocalRepositoryProvider),
    ref.watch(intentosBorradoRepositoryProvider),
    ref.watch(relojBorradoProvider),
  ),
);

/// Provisorio hasta que el motor de sync esté en la app (#178 / #182): ver
/// [SincronizadorManualProvisorio].
final sincronizadorManualProvider = Provider<SincronizadorManual>(
  (ref) => const SincronizadorManualProvisorio(),
);

final sincronizarAhoraUseCaseProvider = Provider<SincronizarAhoraUseCase>(
  (ref) => SincronizarAhoraUseCase(ref.watch(sincronizadorManualProvider)),
);
