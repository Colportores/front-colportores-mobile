import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tiles/domain/services/puertos_descarga.dart';

/// Conexión del teléfono (puerto [MonitorConectividad]).
///
/// El valor por defecto es **provisorio** y es el de los tests y el modo demo: asume que hay Wi-Fi
/// y nunca avisa un cambio. `main.dart` lo reemplaza con `MonitorConectividadPlus`
/// (`connectivity_plus`, #189), el que lee la conexión real del teléfono. Los tests de las
/// pantallas que cambian con la conexión lo reemplazan con un monitor propio.
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
