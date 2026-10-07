import 'dart:async';

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

/// La conexión de ahora y cada cambio. La primera lectura no pisa a un cambio que llegó antes que
/// ella (el cambio es más nuevo). Mientras no hay lectura (o si el monitor falla) no se sabe cómo
/// está el teléfono: quien lo lee no afirma nada.
final conexionProvider = StreamProvider<TipoConexion>((ref) {
  final monitor = ref.watch(monitorConectividadProvider);
  final salida = StreamController<TipoConexion>();
  StreamSubscription<TipoConexion>? escucha;
  var llegoUnCambio = false;
  salida
    ..onListen = () {
      escucha = monitor.cambios.listen((tipo) {
        llegoUnCambio = true;
        salida.add(tipo);
      }, onError: (Object error, StackTrace rastro) => salida.addError(error, rastro));
      unawaited(
        monitor.actual().then<void>(
          (tipo) {
            if (!llegoUnCambio && !salida.isClosed) salida.add(tipo);
          },
          onError: (Object error, StackTrace rastro) {
            if (!llegoUnCambio && !salida.isClosed) salida.addError(error, rastro);
          },
        ),
      );
    }
    ..onCancel = () => escucha?.cancel();
  ref.onDispose(() => unawaited(salida.close()));
  return salida.stream;
});

final class _MonitorConectividadProvisorio implements MonitorConectividad {
  const _MonitorConectividadProvisorio();

  @override
  Future<TipoConexion> actual() async => TipoConexion.wifi;

  @override
  Stream<TipoConexion> get cambios => const Stream<TipoConexion>.empty();
}
