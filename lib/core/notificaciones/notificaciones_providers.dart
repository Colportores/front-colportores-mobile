import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fakes/permiso_alarmas_exactas_en_memoria.dart';
import 'fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'permiso_alarmas_exactas.dart';
import 'permiso_notificaciones_sistema.dart';

/// El permiso de notificaciones del sistema (HU-NOT-001, vista 24).
///
/// El default es el fake con las notificaciones ya activadas: lo usan los tests y la app sin el
/// canal nativo, y ninguna pantalla pide el permiso sin que se lo pidan. `main.dart` lo reemplaza
/// con [PermisoNotificacionesCanal].
final permisoNotificacionesSistemaProvider = Provider<PermisoNotificacionesSistema>(
  (ref) => PermisoNotificacionesSistemaEnMemoria(),
);

/// El permiso «Alarmas y recordatorios» del sistema (HU-NOT-002, «Aviso exacto»).
///
/// El default es el fake sin ese concepto (`noAplica`): lo usan los tests y la app sin el canal
/// nativo, y no se muestra ningún aviso. `main.dart` lo reemplaza con [PermisoAlarmasExactasCanal].
final permisoAlarmasExactasProvider = Provider<PermisoAlarmasExactas>(
  (ref) => PermisoAlarmasExactasEnMemoria(),
);
