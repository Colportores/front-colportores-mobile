import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/notificaciones/notificaciones_providers.dart';
import '../../../../core/notificaciones/permiso_notificaciones_sistema.dart';
import '../../data/repositories/permiso_notificaciones_repository_impl.dart';
import '../../domain/entities/estado_notificaciones.dart';
import '../../domain/repositories/permiso_notificaciones_repository.dart';

/// Lo que el teléfono recuerda del permiso de notificaciones (HU-NOT-001). En el equipo,
/// `main.dart` lo sobreescribe con el almacén seguro; por defecto (tests), en memoria.
final permisoNotificacionesRepositoryProvider = Provider<PermisoNotificacionesRepository>(
  (ref) => PermisoNotificacionesRepositoryEnMemoria(),
);

/// Sin reintento automático: si no se puede leer el estado, la pantalla ofrece «Reintentar» y el
/// resto de la app sigue sin pedir nada (con el reintento por defecto de Riverpod 3 el error tardaría
/// minutos en llegar).
Duration? _sinReintentos(int intento, Object error) => null;

/// Cómo están las notificaciones en este teléfono y qué contestó la persona (HU-NOT-001, vista 24).
///
/// Vive mientras la pantalla principal lo mira (`_Principal`, en `app.dart`): un cierre de sesión lo
/// suelta y el próximo ingreso lo lee de nuevo. En error (el sistema no contestó, o el almacén no se
/// deja leer) la app **no pide nada**: nunca se deja a nadie atrapado en el pedido.
final notificacionesProvider =
    AsyncNotifierProvider.autoDispose<NotificacionesNotifier, EstadoNotificaciones>(
      NotificacionesNotifier.new,
      retry: _sinReintentos,
    );

class NotificacionesNotifier extends AsyncNotifier<EstadoNotificaciones> {
  /// Sube con cada cambio hecho por la persona: una lectura que empezó antes y llega después (al
  /// volver a la app, mientras contesta el diálogo) no pisa lo que ella acaba de hacer.
  int _version = 0;

  /// «Activar» en curso: un segundo toque (o dos pantallas) comparte el mismo pedido y el diálogo del
  /// sistema se muestra una sola vez.
  Future<ResultadoActivacion>? _activando;

  PermisoNotificacionesSistema get _sistema => ref.read(permisoNotificacionesSistemaProvider);
  PermisoNotificacionesRepository get _repositorio =>
      ref.read(permisoNotificacionesRepositoryProvider);

  @override
  Future<EstadoNotificaciones> build() => _leer();

  Future<EstadoNotificaciones> _leer() async {
    final sistema = _sistema;
    final repositorio = _repositorio;
    var pedido = await repositorio.leerPedido();
    final avisoCerrado = await repositorio.leerAvisoCerrado();
    final estado = await sistema.leerEstado();
    if (estado == EstadoSistemaNotificaciones.activadas && pedido == null) {
      // Ya estaban activadas (otra instalación, o un teléfono que no pregunta): no hay nada que
      // pedir. Si después las apaga, desde la app ya no se pueden activar.
      await repositorio.anotarPedido(PedidoNotificaciones.sistema);
      pedido = PedidoNotificaciones.sistema;
    }
    return EstadoNotificaciones(
      permiso: switch (estado) {
        EstadoSistemaNotificaciones.activadas => EstadoPermisoNotificaciones.activadas,
        EstadoSistemaNotificaciones.sinPreguntar => EstadoPermisoNotificaciones.sinPedir,
        EstadoSistemaNotificaciones.apagadas =>
          pedido == PedidoNotificaciones.sistema
              ? EstadoPermisoNotificaciones.bloqueadas
              : EstadoPermisoNotificaciones.sinPedir,
      },
      pedidoRespondido: pedido != null,
      avisoCerrado: avisoCerrado,
    );
  }

  void _poner(EstadoNotificaciones Function(EstadoNotificaciones actual) cambio) {
    final actual = state.value;
    if (!ref.mounted || actual == null) return;
    _version++;
    state = AsyncData(cambio(actual));
  }

  /// Vuelve a leer lo que dice el sistema, sin pasar por «cargando»: la persona pudo activar o apagar
  /// las notificaciones en los ajustes del teléfono. Si no se puede leer, deja lo que había.
  Future<void> refrescar() async {
    if (_activando != null) return;
    final version = _version;
    try {
      final nuevo = await _leer();
      if (!ref.mounted || version != _version || _activando != null) return;
      state = AsyncData(nuevo);
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.push,
        'NOTIF_REFRESCAR',
        'no se pudo volver a leer el estado de las notificaciones',
        {'error': e.runtimeType.toString()},
      );
    }
  }

  /// «Activar notificaciones»: muestra el diálogo del sistema (una sola vez aunque se toque dos
  /// veces) y deja anotado que ya se le preguntó. Nunca lanza.
  Future<ResultadoActivacion> activar() {
    return _activando ??= _activar().whenComplete(() => _activando = null);
  }

  Future<ResultadoActivacion> _activar() async {
    if (state.value == null) return ResultadoActivacion.fallo;
    final bool concedido;
    try {
      concedido = await _sistema.pedir();
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.push,
        'NOTIF_PEDIR',
        'no se pudo pedir el permiso de notificaciones',
        {'error': e.runtimeType.toString()},
      );
      return ResultadoActivacion.fallo;
    }
    try {
      await _repositorio.anotarPedido(PedidoNotificaciones.sistema);
    } on Object {
      // Anotar es de mejor esfuerzo: lo peor es que el pedido se repita.
    }
    _poner(
      (actual) => actual.copyWith(
        permiso: concedido
            ? EstadoPermisoNotificaciones.activadas
            : EstadoPermisoNotificaciones.bloqueadas,
        pedidoRespondido: true,
      ),
    );
    return concedido ? ResultadoActivacion.activadas : ResultadoActivacion.noConcedido;
  }

  /// «Ahora no» del pedido del primer ingreso: sigue sin molestar, el aviso de Hoy lo recuerda.
  Future<void> ahoraNo() async {
    try {
      await _repositorio.anotarPedido(PedidoNotificaciones.ahoraNo);
    } on Object {
      // De mejor esfuerzo, como al activar.
    }
    _poner((actual) => actual.copyWith(pedidoRespondido: true));
  }

  /// La ✕ del aviso de Hoy: no vuelve a salir en esta instalación.
  Future<void> cerrarAviso() async {
    _poner((actual) => actual.copyWith(avisoCerrado: true));
    try {
      await _repositorio.anotarAvisoCerrado();
    } on Object {
      // De mejor esfuerzo: si no se guarda, vuelve a salir la próxima vez.
    }
  }

  /// Abre los ajustes de notificaciones del teléfono. `false` si no pudo abrirlos.
  Future<bool> abrirAjustes() async {
    try {
      return await _sistema.abrirAjustes();
    } on Object {
      return false;
    }
  }
}
