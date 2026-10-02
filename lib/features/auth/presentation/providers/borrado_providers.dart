import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/reloj/reloj_monotono.dart';
import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../data/repositories/intentos_borrado_repository_impl.dart';
import '../../data/repositories/sincronizador_manual_provisorio.dart';
import '../../domain/repositories/intentos_borrado_repository.dart';
import '../../domain/services/sincronizador_manual.dart';
import '../../domain/usecases/sincronizar_ahora_use_case.dart';
import '../../domain/usecases/verificar_password_borrado_use_case.dart';
import 'db_local_providers.dart';

// Cableado de la confirmación final del borrado de datos locales (HU-AUTH-010, vista 19).

/// Reloj de la espera de intentos (inyectable en tests). Monótono: adelantar la hora del teléfono no
/// destraba la espera ([RelojMonotono]).
final relojBorradoProvider = Provider<DateTime Function()>((ref) => RelojMonotono().ahora);

/// Un borrado de datos locales que ya empezó y falló a mitad (la DB puede estar cerrada y el archivo
/// sin borrar). Vive fuera de la pantalla: si el usuario toca «Volver» y reentra, la vista sigue en
/// «terminar el borrado» en vez de quedar trabada contando una DB que ya no está abierta. Se limpia
/// cuando lo local termina de borrarse.
final class BorradoEmpezado {
  const BorradoEmpezado({required this.incluirBackupDrive});

  final bool incluirBackupDrive;
}

final class BorradoEmpezadoNotifier extends Notifier<BorradoEmpezado?> {
  @override
  BorradoEmpezado? build() => null;

  void marcar({required bool incluirBackupDrive}) =>
      state = BorradoEmpezado(incluirBackupDrive: incluirBackupDrive);

  void limpiar() => state = null;
}

final borradoEmpezadoProvider = NotifierProvider<BorradoEmpezadoNotifier, BorradoEmpezado?>(
  BorradoEmpezadoNotifier.new,
);

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
