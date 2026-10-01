import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tiles/domain/services/puertos_descarga.dart';

/// Conexión del teléfono (puerto [MonitorConectividad]).
///
/// **Provisorio:** el repo no tiene librería de conectividad y elegirla es de Cristian (#189), así
/// que hasta entonces se asume que hay conexión y nunca avisa un cambio. Las pantallas que muestran
/// "sin conexión" (vista 19, artboard 09) lo van a mostrar cuando esto tenga una fuente real; los
/// tests lo reemplazan con un monitor propio.
final monitorConectividadProvider = Provider<MonitorConectividad>(
  (ref) => const _MonitorConectividadProvisorio(),
);

final class _MonitorConectividadProvisorio implements MonitorConectividad {
  const _MonitorConectividadProvisorio();

  @override
  Future<TipoConexion> actual() async => TipoConexion.wifi;

  @override
  Stream<TipoConexion> get cambios => const Stream<TipoConexion>.empty();
}
