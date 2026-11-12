import 'dart:async';

import '../permiso_notificaciones_sistema.dart';

/// [PermisoNotificacionesSistema] en memoria.
///
/// **No es código de producción.** Es el default de los tests (con las notificaciones ya activadas,
/// así ninguna pantalla pide el permiso sin que el test lo diga) y de la app sin el canal nativo.
final class PermisoNotificacionesSistemaEnMemoria implements PermisoNotificacionesSistema {
  PermisoNotificacionesSistemaEnMemoria({this.estado = EstadoSistemaNotificaciones.activadas});

  /// Lo que dice el sistema ahora. [pedir] lo cambia según [respuestaAlPedir].
  EstadoSistemaNotificaciones estado;

  /// Qué contesta la persona al diálogo del sistema.
  bool respuestaAlPedir = true;

  /// Si es `true`, [leerEstado] lanza [PermisoNotificacionesException].
  bool fallaAlLeer = false;

  /// Si es `true`, [pedir] lanza [PermisoNotificacionesException] (el diálogo no llegó a mostrarse).
  bool fallaAlPedir = false;

  /// Si no es `null`, [pedir] espera a que se complete (el diálogo sigue abierto).
  Completer<void>? dialogoAbierto;

  /// Si no es `null`, [leerEstado] espera a que se complete (el sistema todavía no contestó).
  Completer<void>? lecturaDemorada;

  /// Si no es `null`, [abrirAjustes] espera a que se complete (los ajustes tardan en abrirse).
  Completer<void>? ajustesDemorados;

  /// Si es `false`, [abrirAjustes] devuelve `false` (el teléfono no tiene esa pantalla).
  bool puedeAbrirAjustes = true;

  /// Cuántas veces se mostró el diálogo del sistema ([pedir]).
  int pedidos = 0;

  /// Cuántas veces se abrieron los ajustes.
  int ajustesAbiertos = 0;

  /// Cuántas veces se leyó el estado.
  int lecturas = 0;

  @override
  Future<EstadoSistemaNotificaciones> leerEstado() async {
    lecturas++;
    final demora = lecturaDemorada;
    if (demora != null) await demora.future;
    if (fallaAlLeer) throw const PermisoNotificacionesException(operacion: 'estado');
    return estado;
  }

  @override
  Future<bool> pedir() async {
    pedidos++;
    if (fallaAlPedir) throw const PermisoNotificacionesException(operacion: 'pedir');
    final abierto = dialogoAbierto;
    if (abierto != null) await abierto.future;
    if (estado == EstadoSistemaNotificaciones.activadas) return true;
    estado = respuestaAlPedir
        ? EstadoSistemaNotificaciones.activadas
        : EstadoSistemaNotificaciones.apagadas;
    return respuestaAlPedir;
  }

  @override
  Future<bool> abrirAjustes() async {
    ajustesAbiertos++;
    final demora = ajustesDemorados;
    if (demora != null) await demora.future;
    return puedeAbrirAjustes;
  }
}
