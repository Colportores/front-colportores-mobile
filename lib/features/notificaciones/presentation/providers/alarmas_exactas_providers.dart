import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/notificaciones/notificaciones_providers.dart';
import '../../../../core/notificaciones/permiso_alarmas_exactas.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import 'preferencias_recordatorios_providers.dart';

// Cableado de «Aviso exacto» (HU-NOT-002, decisión de Cristian del 27/10): el permiso «Alarmas y
// recordatorios» de Android decide si los recordatorios suenan a la hora justa. La vista 24 avisa si
// está apagado y lleva al ajuste; al volver, los recordatorios ya programados se reprograman.

/// Sin reintento automático: si no se puede leer el permiso, la vista 24 no muestra nada y los
/// recordatorios siguen (inexactos).
Duration? _sinReintentos(int intento, Object error) => null;

/// Cómo están las alarmas exactas en este teléfono.
///
/// Vive mientras alguien lo mira: la pantalla principal (`reprogramacionPorAlarmasProvider`, en
/// `app.dart`) lo mantiene vivo toda la sesión y la vista 24 lo lee. Se vuelve a leer cada vez que se
/// vuelve a la app (la persona pudo prender o apagar el permiso en los ajustes). **Cada vez que el
/// estado cambia —y al leerlo por primera vez— se reprograman los recordatorios** de las visitas
/// pendientes: con el permiso nuevo, pasan a exactos; con el permiso quitado (Android cancela las
/// alarmas exactas al quitarlo), vuelven a quedar programados inexactos.
///
/// Nunca queda en error: si el sistema no contesta se lee como [EstadoAlarmasExactas.noAplica] (no se
/// muestra nada, el recordatorio se programa inexacto) y se vuelve a intentar al volver a la app.
final alarmasExactasProvider =
    AsyncNotifierProvider.autoDispose<AlarmasExactasNotifier, EstadoAlarmasExactas>(
      AlarmasExactasNotifier.new,
      retry: _sinReintentos,
    );

class AlarmasExactasNotifier extends AsyncNotifier<EstadoAlarmasExactas> {
  /// La lectura en curso: dos regresos seguidos a la app comparten la misma.
  Future<void>? _leyendo;

  /// La reprogramación en curso: un cambio que llega mientras corre pide otra al terminar.
  bool _reprogramando = false;
  bool _reprogramarOtraVez = false;

  PermisoAlarmasExactas get _sistema => ref.read(permisoAlarmasExactasProvider);

  @override
  Future<EstadoAlarmasExactas> build() async {
    final ciclo = AppLifecycleListener(onResume: () => unawaited(refrescar()));
    ref.onDispose(ciclo.dispose);
    final estado = await _leer() ?? EstadoAlarmasExactas.noAplica;
    // Al arrancar la app, los avisos que Android pudo haber cancelado (permiso quitado con la app
    // cerrada) se vuelven a programar con el modo de ahora. Recién cuando `build` terminó: mientras
    // corre, `ref` todavía no está listo para leer otros providers de la sesión.
    if (estado != EstadoAlarmasExactas.noAplica) unawaited(Future<void>.microtask(_reprogramar));
    return estado;
  }

  /// `null` si el sistema no contestó.
  Future<EstadoAlarmasExactas?> _leer() async {
    try {
      return await _sistema.leerEstado();
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.push,
        'ALARMAS_EXACTAS_LEER',
        'no se pudo leer el permiso de alarmas exactas',
        {'error': e.runtimeType.toString()},
      );
      return null;
    }
  }

  /// Vuelve a leer el permiso, sin pasar por «cargando». Si cambió, reprograma los recordatorios. Si
  /// no se puede leer, deja lo que había.
  Future<void> refrescar() => _leyendo ??= _refrescar().whenComplete(() => _leyendo = null);

  Future<void> _refrescar() async {
    final antes = state.value;
    if (antes == null) return;
    final nuevo = await _leer();
    if (nuevo == null || !ref.mounted || nuevo == antes) return;
    state = AsyncData(nuevo);
    await _reprogramar();
  }

  /// Reprograma los recordatorios de las visitas pendientes con el modo de ahora. De a una a la vez:
  /// si llega otro pedido mientras corre, se hace otra al terminar.
  Future<void> _reprogramar() async {
    if (_reprogramando) {
      _reprogramarOtraVez = true;
      return;
    }
    _reprogramando = true;
    try {
      do {
        _reprogramarOtraVez = false;
        if (!ref.mounted) return;
        final colportorId = ref.read(sesionProvider).value?.usuarioId;
        if (colportorId == null) return;
        await ref.read(reprogramarRecordatoriosUseCaseProvider).call(colportorId);
      } while (_reprogramarOtraVez);
    } on Object catch (e) {
      // El caso de uso no lanza; si el cableado lo hace, la app sigue.
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ALARMAS_EXACTAS_REPROGRAMAR',
        'no se pudieron reprogramar los recordatorios al cambiar el permiso de alarmas exactas',
        {'error': e.runtimeType.toString()},
      );
    } finally {
      _reprogramando = false;
    }
  }

  /// Abre «Alarmas y recordatorios» en el teléfono. `false` si no pudo abrirlo. Nunca lanza.
  Future<bool> abrirAjustes() async {
    try {
      return await _sistema.abrirAjustes();
    } on Object {
      return false;
    }
  }
}

/// Mantiene vivo [alarmasExactasProvider] toda la sesión: lo mira la pantalla principal (`_Principal`,
/// en `app.dart`) para que el permiso se lea al abrir la app y al volver a ella aunque la vista 24 no
/// esté abierta, y los recordatorios no queden inexactos con el permiso ya prendido.
final reprogramacionPorAlarmasProvider = Provider.autoDispose<void>((ref) {
  ref.listen(alarmasExactasProvider, (_, _) {});
});
