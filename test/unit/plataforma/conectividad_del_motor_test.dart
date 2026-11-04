// El motor distingue Wi-Fi de datos móviles para el ahorro de datos (HU-SYNC-008): este adaptador
// lo saca del monitor de conectividad que ya usa la app.
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/plataforma/conectividad_del_motor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/tiles_falsos.dart';

void main() {
  late ConectividadFalsa monitor;
  late ConectividadDelMotor puerto;

  setUp(() {
    monitor = ConectividadFalsa();
    puerto = ConectividadDelMotor(monitor);
  });

  test('con Wi-Fi hay red y es Wi-Fi', () async {
    monitor.tipo = TipoConexion.wifi;

    expect(await puerto.isOnline, isTrue);
    expect(await puerto.isOnWifi, isTrue);
  });

  test('con datos móviles hay red pero no es Wi-Fi', () async {
    monitor.tipo = TipoConexion.datosMoviles;

    expect(await puerto.isOnline, isTrue);
    expect(await puerto.isOnWifi, isFalse);
  });

  test('sin conexión no hay red ni Wi-Fi', () async {
    monitor.tipo = TipoConexion.sinConexion;

    expect(await puerto.isOnline, isFalse);
    expect(await puerto.isOnWifi, isFalse);
  });

  test('wifiChanges avisa cada vez que se gana o se pierde el Wi-Fi, sin repetir', () async {
    final vistos = <bool>[];
    final escucha = puerto.wifiChanges.listen(vistos.add);

    monitor
      ..cambiarA(TipoConexion.datosMoviles)
      ..cambiarA(TipoConexion.sinConexion) // sigue sin Wi-Fi: no se repite el false
      ..cambiarA(TipoConexion.wifi)
      ..cambiarA(TipoConexion.datosMoviles);
    await Future<void>.delayed(Duration.zero);
    await escucha.cancel();

    expect(vistos, [false, true, false]);
  });

  test('onlineChanges sigue avisando solo el paso entre sin conexión y con conexión', () async {
    final vistos = <bool>[];
    final escucha = puerto.onlineChanges.listen(vistos.add);

    monitor
      ..cambiarA(TipoConexion.datosMoviles)
      ..cambiarA(TipoConexion.wifi) // de datos a Wi-Fi no cambia «online»
      ..cambiarA(TipoConexion.sinConexion);
    await Future<void>.delayed(Duration.zero);
    await escucha.cancel();

    expect(vistos, [true, false]);
  });
}
