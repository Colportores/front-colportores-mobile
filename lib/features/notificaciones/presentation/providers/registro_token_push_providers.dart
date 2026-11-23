import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/config/config_supabase.dart';
import '../../../../core/notificaciones/notificaciones_providers.dart';
import '../../../tiles/domain/services/puertos_descarga.dart' show TipoConexion;
import '../../data/repositories/token_push_repository_impl.dart';
import '../../domain/repositories/token_push_repository.dart';
import '../../domain/services/registro_token_push.dart';
import 'notificaciones_providers.dart';

// Cableado del registro del teléfono para las push (HU-NOT-001, «Token FCM», #414): al dar el permiso
// la app obtiene el token de FCM y lo sube con la función del servidor `registrar_mi_token_push`; si
// el sistema lo rota, lo vuelve a subir; al cerrar sesión, lo vacía. No hay vista: no hay nada que
// mostrar (nota de 24A·05).

/// Dónde se guarda el token: `usuario.fcm_token`, con la sesión de la app. Sin Supabase (tests,
/// demo) no hay servidor: un repositorio en memoria.
final tokenPushRepositoryProvider = Provider<TokenPushRepository>(
  (ref) => ConfigSupabase.configurada
      ? TokenPushSupabase.conCliente(Supabase.instance.client)
      : TokenPushEnMemoria(),
);

/// El registro del token de la colportora de esta sesión. Vive mientras la pantalla principal lo mira
/// ([mantenerTokenPushProvider]) o corre el cierre de sesión: con la sesión se va, y la de otra cuenta
/// arranca con uno nuevo (lo que se subió era de la anterior). No mira la sesión a propósito: un
/// provider que la observa se reconstruye en medio de la salida de la pantalla principal.
final registroTokenPushProvider = Provider.autoDispose<RegistroTokenPush>((ref) {
  final push = ref.watch(pushRemotasProvider);
  return RegistroTokenPush(
    servidor: ref.watch(tokenPushRepositoryProvider),
    obtenerToken: push.obtenerToken,
  );
});

/// Lo que `main.dart` pone en [retiroTokenPushProvider]: vacía el token en el servidor.
Future<void> Function() retirarTokenPush(Ref ref) =>
    () => ref.read(registroTokenPushProvider).retirar();

/// Mantiene al día el token del teléfono mientras haya sesión (`_Principal`, en `app.dart`, lo mira).
///
/// - **Con las notificaciones activadas** (al dar el permiso, o ya dado) sube el token al abrir. Sin
///   el permiso no sube nada: la colportora no pidió avisos.
/// - Si el sistema le da un token nuevo (`onTokenRefresh`), lo sube.
/// - Si algo quedó sin subir (sin conexión), lo reintenta al volver la señal y al volver a la app; y
///   al volver a la app pasadas 24 h sin haberlo confirmado, lo repasa (en silencio, sin avisar).
final mantenerTokenPushProvider = Provider.autoDispose<void>((ref) {
  final activadas = ref.watch(
    notificacionesProvider.select((estado) => estado.value?.activadas ?? false),
  );
  if (!activadas) return;
  final registro = ref.watch(registroTokenPushProvider);
  final push = ref.watch(pushRemotasProvider);

  final rotaciones = push.tokenRotado.listen(
    (token) => unawaited(registro.sincronizar(token: token)),
  );
  final ciclo = AppLifecycleListener(onResume: () => unawaited(registro.sincronizarSiHaceFalta()));
  ref.listen(conexionProvider, (_, nueva) {
    final conexion = nueva.value;
    if (conexion == null || conexion == TipoConexion.sinConexion) return;
    if (registro.hayPendiente) unawaited(registro.sincronizar());
  });
  ref.onDispose(() {
    unawaited(rotaciones.cancel());
    ciclo.dispose();
  });
  unawaited(registro.sincronizar());
});
