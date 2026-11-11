import 'dart:async';

import '../permiso_alarmas_exactas.dart';

/// [PermisoAlarmasExactas] en memoria.
///
/// **No es código de producción.** Es el default de los tests y de la app sin el canal nativo, con
/// [EstadoAlarmasExactas.noAplica]: ninguna pantalla avisa de las alarmas ni reprograma nada sin que el
/// test lo diga.
final class PermisoAlarmasExactasEnMemoria implements PermisoAlarmasExactas {
  PermisoAlarmasExactasEnMemoria({this.estado = EstadoAlarmasExactas.noAplica});

  /// Lo que dice el sistema ahora.
  EstadoAlarmasExactas estado;

  /// Si es `true`, [leerEstado] lanza [PermisoAlarmasExactasException].
  bool fallaAlLeer = false;

  /// Si no es `null`, [leerEstado] espera a que se complete (el sistema todavía no contestó).
  Completer<void>? lecturaDemorada;

  /// Si no es `null`, [abrirAjustes] espera a que se complete (los ajustes tardan en abrirse).
  Completer<void>? ajustesDemorados;

  /// Si es `false`, [abrirAjustes] devuelve `false` (el teléfono no tiene esa pantalla).
  bool puedeAbrirAjustes = true;

  /// Si es `true`, [abrirAjustes] lanza [PermisoAlarmasExactasException].
  bool fallaAlAbrir = false;

  /// Cuántas veces se leyó el estado.
  int lecturas = 0;

  /// Cuántas veces se abrieron los ajustes.
  int ajustesAbiertos = 0;

  @override
  Future<EstadoAlarmasExactas> leerEstado() async {
    lecturas++;
    final demora = lecturaDemorada;
    if (demora != null) await demora.future;
    if (fallaAlLeer) throw const PermisoAlarmasExactasException(operacion: 'estado');
    return estado;
  }

  @override
  Future<bool> abrirAjustes() async {
    ajustesAbiertos++;
    final demora = ajustesDemorados;
    if (demora != null) await demora.future;
    if (fallaAlAbrir) throw const PermisoAlarmasExactasException(operacion: 'abrirAjustes');
    return puedeAbrirAjustes;
  }
}
