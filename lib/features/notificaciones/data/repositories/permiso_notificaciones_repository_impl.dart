import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/permiso_notificaciones_repository.dart';

/// [PermisoNotificacionesRepository] sobre el almacén seguro: `ClaveSegura.permisoNotificaciones`
/// (`ahora_no` o `sistema`) y `ClaveSegura.avisoNotificacionesCerrado` (`1`).
///
/// Serializa las operaciones: cada una espera a la anterior, así una lectura pedida después de una
/// anotación en vuelo ve lo nuevo. Un valor que no se reconoce cuenta como «nunca se pidió». Anotar
/// nunca lanza (queda en el log, sin datos de la persona); leer lanza si el almacén falla.
final class PermisoNotificacionesRepositoryImpl implements PermisoNotificacionesRepository {
  PermisoNotificacionesRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  static const _ahoraNo = 'ahora_no';
  static const _sistema = 'sistema';
  static const _cerrado = '1';

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  Future<PedidoNotificaciones?> _leerPedido() async {
    return switch (await _almacen.leer(ClaveSegura.permisoNotificaciones)) {
      _ahoraNo => PedidoNotificaciones.ahoraNo,
      _sistema => PedidoNotificaciones.sistema,
      _ => null,
    };
  }

  @override
  Future<PedidoNotificaciones?> leerPedido() => _encolar(_leerPedido);

  @override
  Future<void> anotarPedido(PedidoNotificaciones pedido) => _encolar(() async {
    try {
      // `ahoraNo` nunca pisa a `sistema`: después del diálogo del sistema, la app ya no puede
      // activar las notificaciones; un «Ahora no» viejo no lo desanota.
      if (pedido == PedidoNotificaciones.ahoraNo && await _leerPedido() != null) return;
      await _almacen.escribir(
        ClaveSegura.permisoNotificaciones,
        pedido == PedidoNotificaciones.sistema ? _sistema : _ahoraNo,
      );
    } on Object catch (e) {
      _log.warn(
        LogModulo.push,
        'PERMISO_NOTIF_ESCRIBIR',
        'no se pudo guardar lo contestado del permiso de notificaciones',
        {'error': e.runtimeType.toString()},
      );
    }
  });

  @override
  Future<bool> leerAvisoCerrado() =>
      _encolar(() async => await _almacen.leer(ClaveSegura.avisoNotificacionesCerrado) == _cerrado);

  @override
  Future<void> anotarAvisoCerrado() => _encolar(() async {
    try {
      await _almacen.escribir(ClaveSegura.avisoNotificacionesCerrado, _cerrado);
    } on Object catch (e) {
      _log.warn(
        LogModulo.push,
        'AVISO_NOTIF_ESCRIBIR',
        'no se pudo guardar que se cerró el aviso de notificaciones',
        {'error': e.runtimeType.toString()},
      );
    }
  });
}

/// [PermisoNotificacionesRepository] en memoria: el default de los tests y de la app sin Keystore.
/// **No es código de producción**: `main.dart` lo reemplaza por [PermisoNotificacionesRepositoryImpl].
final class PermisoNotificacionesRepositoryEnMemoria implements PermisoNotificacionesRepository {
  PermisoNotificacionesRepositoryEnMemoria({this.pedido, this.avisoCerrado = false});

  PedidoNotificaciones? pedido;
  bool avisoCerrado;

  /// Con `true`, las lecturas lanzan (simula un almacén roto).
  bool fallaAlLeer = false;

  /// Con `true`, las anotaciones no guardan nada (simula un almacén que falla al escribir).
  bool fallaAlAnotar = false;

  /// Cuántas veces se anotó el pedido.
  int anotaciones = 0;

  @override
  Future<PedidoNotificaciones?> leerPedido() async {
    if (fallaAlLeer) throw const AlmacenSeguroException(operacion: 'leer');
    return pedido;
  }

  @override
  Future<void> anotarPedido(PedidoNotificaciones nuevo) async {
    anotaciones++;
    if (fallaAlAnotar) return;
    if (nuevo == PedidoNotificaciones.ahoraNo && pedido != null) return;
    pedido = nuevo;
  }

  @override
  Future<bool> leerAvisoCerrado() async {
    if (fallaAlLeer) throw const AlmacenSeguroException(operacion: 'leer');
    return avisoCerrado;
  }

  @override
  Future<void> anotarAvisoCerrado() async {
    if (fallaAlAnotar) return;
    avisoCerrado = true;
  }
}
