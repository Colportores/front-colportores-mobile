import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/tiles/domain/services/puertos_descarga.dart';

/// [MonitorConectividad] sobre `connectivity_plus` (decisión d6 de #189).
///
/// Solo sirve para saber de qué tipo es la conexión y cuándo cambia: que haya Wi-Fi no quiere
/// decir que haya internet (un portal cautivo, un router sin salida), y eso lo decide la respuesta
/// real del servidor. Por eso un fallo de la descarga por red no depende de esto: queda en pausa y
/// sigue con el próximo cambio o cuando el colportor toca «Descargar mapa».
final class MonitorConectividadPlus implements MonitorConectividad {
  MonitorConectividadPlus({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<TipoConexion> actual() async {
    try {
      return tipoDe(await _connectivity.checkConnectivity());
    } on Exception {
      // No se pudo leer: se la trata como datos móviles, la que no baja sola y sí con el permiso
      // del colportor.
      return TipoConexion.datosMoviles;
    }
  }

  @override
  Stream<TipoConexion> get cambios => _connectivity.onConnectivityChanged.map(tipoDe).distinct();

  /// El tipo para la política de descarga. Wi-Fi o cable (no miden el consumo) mandan sobre
  /// los datos móviles; sin ninguna conexión es `sinConexion`; una conexión que no se sabe qué es
  /// (VPN sola, Bluetooth, otra) cuenta como datos móviles, que es lo prudente.
  static TipoConexion tipoDe(List<ConnectivityResult> resultados) {
    final activas = resultados.where((r) => r != ConnectivityResult.none).toSet();
    if (activas.isEmpty) return TipoConexion.sinConexion;
    if (activas.contains(ConnectivityResult.wifi) ||
        activas.contains(ConnectivityResult.ethernet)) {
      return TipoConexion.wifi;
    }
    return TipoConexion.datosMoviles;
  }
}
