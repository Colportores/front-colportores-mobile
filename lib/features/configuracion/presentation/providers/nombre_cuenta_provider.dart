import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/database/sesion_usuario_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';

/// Nombre de la cuenta para el saludo del resumen del día y para Configuración («Lucía Silva»):
/// el de la sesión y, si la sesión no lo trae, la copia guardada en la DB cifrada (#243). `null`
/// si no hay ninguno (ingreso con Google): la pantalla muestra el saludo o el correo sin nombre.
final nombreCuentaProvider = Provider<String?>((ref) {
  final delaSesion = _limpio(ref.watch(sesionProvider).value?.nombre);
  return delaSesion ?? _limpio(ref.watch(nombreGuardadoProvider).value);
});

/// La copia local del nombre del usuario de la sesión actual. `null` sin sesión, sin DB abierta, o
/// si lo guardado es de otro usuario.
final nombreGuardadoProvider = FutureProvider<String?>((ref) async {
  final sesion = ref.watch(sesionProvider).value;
  final copia = ref.watch(sesionUsuarioLocalDataSourceProvider);
  if (sesion == null || copia == null) return null;
  try {
    return await copia.leer(sesion.usuarioId);
  } on Object {
    return null;
  }
});

/// Mantiene al día la copia local: cada vez que hay sesión con nombre y la DB está abierta, la
/// guarda (la raíz de la app lo observa). Mejor esfuerzo: si no se puede escribir, la sesión sigue
/// trayendo el nombre.
final copiaNombreSesionProvider = Provider<void>((ref) {
  void guardar() {
    final sesion = ref.read(sesionProvider).value;
    final nombre = _limpio(sesion?.nombre);
    final copia = ref.read(sesionUsuarioLocalDataSourceProvider);
    if (sesion == null || nombre == null || copia == null) return;
    unawaited(
      copia
          .guardar(sesion.usuarioId, nombre)
          .then((_) => ref.invalidate(nombreGuardadoProvider))
          .catchError((Object e) {
            AppLogger.instance.warn(
              LogModulo.db,
              'NOMBRE_COPIA_FAIL',
              'no se pudo guardar la copia local del nombre',
            );
          }),
    );
  }

  ref
    ..listen(sesionProvider, (_, _) => guardar())
    ..listen(dbLocalProvider, (_, _) => guardar());
  guardar();
});

String? _limpio(String? nombre) {
  final limpio = nombre?.trim();
  return limpio == null || limpio.isEmpty ? null : limpio;
}
