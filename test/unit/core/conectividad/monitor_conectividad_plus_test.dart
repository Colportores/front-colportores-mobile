// Test del monitor de conectividad sobre connectivity_plus, con la librería simulada.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/monitor_conectividad_plus.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ConnectivityFalsa implements Connectivity {
  List<ConnectivityResult> actual = [ConnectivityResult.wifi];
  Object? falla;
  final cambios = StreamController<List<ConnectivityResult>>.broadcast(sync: true);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (falla case final error?) throw error;
    return actual;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => cambios.stream;
}

void main() {
  const wifi = ConnectivityResult.wifi;
  const movil = ConnectivityResult.mobile;
  const nada = ConnectivityResult.none;

  group('tipoDe', () {
    test('sin ninguna conexión es sinConexion', () {
      expect(MonitorConectividadPlus.tipoDe(const []), TipoConexion.sinConexion);
      expect(MonitorConectividadPlus.tipoDe(const [nada]), TipoConexion.sinConexion);
    });

    test('Wi-Fi o cable es wifi: no gastan datos', () {
      expect(MonitorConectividadPlus.tipoDe(const [wifi]), TipoConexion.wifi);
      expect(
        MonitorConectividadPlus.tipoDe(const [ConnectivityResult.ethernet]),
        TipoConexion.wifi,
      );
    });

    test('el móvil es datosMoviles', () {
      expect(MonitorConectividadPlus.tipoDe(const [movil]), TipoConexion.datosMoviles);
    });

    test('Wi-Fi y móvil juntos es wifi: manda el que no mide el consumo', () {
      expect(MonitorConectividadPlus.tipoDe(const [movil, wifi]), TipoConexion.wifi);
      expect(
        MonitorConectividadPlus.tipoDe(const [wifi, movil, ConnectivityResult.vpn]),
        TipoConexion.wifi,
      );
    });

    test(
      'una conexión que no se sabe qué es (VPN sola, Bluetooth, otra) cuenta como datos móviles',
      () {
        for (final rara in [
          ConnectivityResult.vpn,
          ConnectivityResult.bluetooth,
          ConnectivityResult.other,
        ]) {
          expect(
            MonitorConectividadPlus.tipoDe([rara]),
            TipoConexion.datosMoviles,
            reason: '$rara',
          );
        }
      },
    );

    test('«none» junto a una conexión real no la anula', () {
      expect(MonitorConectividadPlus.tipoDe(const [nada, wifi]), TipoConexion.wifi);
    });
  });

  group('actual', () {
    test('traduce lo que informa la librería', () async {
      final falsa = _ConnectivityFalsa()..actual = [movil];

      expect(
        await MonitorConectividadPlus(connectivity: falsa).actual(),
        TipoConexion.datosMoviles,
      );
    });

    test(
      'si no se pudo leer, se la trata como datos móviles: no baja sola, sí con permiso',
      () async {
        final falsa = _ConnectivityFalsa()..falla = Exception('sin plugin');

        expect(
          await MonitorConectividadPlus(connectivity: falsa).actual(),
          TipoConexion.datosMoviles,
        );
      },
    );
  });

  group('cambios', () {
    test('emite cada cambio de tipo, traducido, y no repite el mismo seguido', () async {
      final falsa = _ConnectivityFalsa();
      final emitidos = <TipoConexion>[];
      final suscripcion = MonitorConectividadPlus(connectivity: falsa).cambios.listen(emitidos.add);

      falsa.cambios
        ..add([wifi])
        ..add([wifi, movil])
        ..add([nada])
        ..add([nada])
        ..add([movil])
        ..add([wifi]);
      await Future<void>.delayed(Duration.zero);

      expect(emitidos, [
        TipoConexion.wifi,
        TipoConexion.sinConexion,
        TipoConexion.datosMoviles,
        TipoConexion.wifi,
      ]);
      await suscripcion.cancel();
    });
  });
}
