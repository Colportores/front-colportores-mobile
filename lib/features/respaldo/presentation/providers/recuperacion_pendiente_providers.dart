import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../data/datasources/lector_de_lo_recuperado_drift.dart';
import '../../domain/repositories/recuperacion_resuelta_repository.dart';
import '../../domain/services/lector_de_lo_recuperado.dart';

/// Si la app ofrece el asistente de recuperación del primer arranque (HU-SYNC-006, vista 34).
/// Apagado por defecto —los tests de las demás pantallas no lo atraviesan—; `main.dart` lo enciende.
final asistenteDeRecuperacionHabilitadoProvider = Provider<bool>((ref) => false);

/// Qué usuarios ya resolvieron el asistente en este teléfono. Por defecto no se ofrece nunca;
/// `main.dart` lo reemplaza por el almacén seguro.
final recuperacionResueltaRepositoryProvider = Provider<RecuperacionResueltaRepository>(
  (ref) => const RecuperacionNuncaSeOfrece(),
);

/// Lo que hay en la base de este teléfono. Lee la base abierta **cada vez**: una recuperación puede
/// reemplazarla.
final lectorDeLoRecuperadoProvider = Provider<LectorDeLoRecuperado>(
  (ref) => LectorDeLoRecuperadoDrift(() => ref.read(dbLocalProvider)),
);

/// Riverpod 3 reintenta solo un provider que falla: acá un fallo se resuelve como «no se ofrece».
Duration? _sinReintentos(int intento, Object error) => null;

/// Si hay que ofrecerle el asistente de recuperación al usuario con la sesión iniciada: no lo
/// resolvió todavía en este teléfono **y** la base está vacía (un teléfono sin datos).
///
/// Se resuelve **una vez** por usuario y se queda así hasta que el asistente termina
/// ([terminar]): una recuperación reemplaza la base y no puede sacar a la persona del asistente
/// antes de que vea el resultado.
///
/// Si no se pudo leer la marca o la base, no se ofrece: la recuperación nunca se ofrece sobre algo
/// que no se pudo mirar, y la app no se frena por eso. Con datos ya guardados, se anota como
/// resuelto: la recuperación nunca pisa lo que hay.
final recuperacionPendienteProvider = AsyncNotifierProvider<RecuperacionPendiente, bool>(
  RecuperacionPendiente.new,
  retry: _sinReintentos,
);

class RecuperacionPendiente extends AsyncNotifier<bool> {
  String? _usuarioId;

  @override
  Future<bool> build() async {
    final usuarioId = ref.watch(sesionProvider.select((s) => s.value?.usuarioId));
    _usuarioId = usuarioId;
    if (usuarioId == null) return false;
    final repo = ref.read(recuperacionResueltaRepositoryProvider);
    try {
      if (await repo.estaResuelta(usuarioId)) return false;
      if (!await ref.read(lectorDeLoRecuperadoProvider).baseSinDatos()) {
        await repo.marcarResuelta(usuarioId);
        return false;
      }
      return true;
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.backup,
        'RECUPERACION_OFRECER',
        'no se pudo decidir si ofrecer la recuperación: no se ofrece',
        {'error': e.runtimeType.toString()},
      );
      return false;
    }
  }

  /// El asistente terminó (recuperó, o la persona eligió «Empezar sin recuperar»): se anota para este
  /// usuario y la raíz sigue a la pantalla siguiente. Nunca lanza.
  Future<void> terminar() async {
    final usuarioId = _usuarioId;
    if (usuarioId != null) {
      await ref.read(recuperacionResueltaRepositoryProvider).marcarResuelta(usuarioId);
    }
    if (ref.mounted) state = const AsyncData(false);
  }
}
