import 'package:sync_engine/sync_engine.dart';

import '../features/tiles/domain/services/puertos_descarga.dart';

/// [ConnectivityPort] del motor sobre el [MonitorConectividad] que ya usa la app
/// (`connectivity_plus`, #189): un trigger de §5.2 es «volvió la red».
///
/// Que haya Wi-Fi no quiere decir que haya internet (un portal cautivo): eso lo decide la
/// respuesta real del servidor, y un push que falla por red queda `PENDING` y sube al próximo
/// trigger. Por eso basta con avisar el paso de sin conexión a con conexión.
///
/// Para el ahorro de datos (HU-SYNC-008) además distingue Wi-Fi de datos móviles. Con Wi-Fi y datos
/// a la vez, [MonitorConectividad] responde Wi-Fi: es la red que el sistema usa para el tráfico.
final class ConectividadDelMotor implements ConnectivityPort {
  const ConectividadDelMotor(this._monitor);

  final MonitorConectividad _monitor;

  @override
  Stream<bool> get onlineChanges =>
      _monitor.cambios.map((tipo) => tipo != TipoConexion.sinConexion).distinct();

  @override
  Future<bool> get isOnline async => await _monitor.actual() != TipoConexion.sinConexion;

  @override
  Future<bool> get isOnWifi async => await _monitor.actual() == TipoConexion.wifi;

  @override
  Stream<bool> get wifiChanges =>
      _monitor.cambios.map((tipo) => tipo == TipoConexion.wifi).distinct();
}
