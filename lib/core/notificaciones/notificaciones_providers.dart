import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'fakes/push_remotas_en_memoria.dart';
import 'permiso_notificaciones_sistema.dart';
import 'push_remotas.dart';

/// El permiso de notificaciones del sistema (HU-NOT-001, vista 24).
///
/// El default es el fake con las notificaciones ya activadas: lo usan los tests y la app sin el
/// canal nativo, y ninguna pantalla pide el permiso sin que se lo pidan. `main.dart` lo reemplaza
/// con [PermisoNotificacionesCanal].
final permisoNotificacionesSistemaProvider = Provider<PermisoNotificacionesSistema>(
  (ref) => PermisoNotificacionesSistemaEnMemoria(),
);

/// Las push remotas (HU-NOT-003, ADR-014).
///
/// El default es el fake que no recibe nada: todavía no hay `firebase_messaging` en el proyecto (falta
/// el proyecto de Firebase y sus archivos de configuración). Cuando lleguen, `main.dart` lo
/// reemplaza con el adaptador de producción.
final pushRemotasProvider = Provider<PushRemotas>((ref) => PushRemotasEnMemoria());
