// Al cerrar la jornada se pide el respaldo en Drive (HU-JOR-002 → HU-SYNC-005) sin que el cierre
// espere ni se rompa por él.
import 'dart:async';

import 'package:colportores_mobile/features/jornada/data/services/disparador_backup_respaldo.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Servicio implements ServicioRespaldo {
  _Servicio({this.espera});

  final Completer<void>? espera;
  final List<OrigenRespaldo> pedidos = [];

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    pedidos.add(origen);
    await espera?.future;
    return const RespaldoOmitido(MotivoOmision.sinWifi);
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async =>
      const VerificacionOmitida(MotivoOmision.sinWifi);
}

void main() {
  test('pide el respaldo del cierre de jornada', () async {
    final servicio = _Servicio();

    await DisparadorBackupRespaldo(servicio).solicitar('col-1');

    expect(servicio.pedidos, [OrigenRespaldo.cierreDeJornada]);
    expect(OrigenRespaldo.cierreDeJornada.esAutomatico, isTrue, reason: 'pide Wi-Fi y batería');
  });

  test('vuelve enseguida: el cierre no espera a que termine la subida', () async {
    final servicio = _Servicio(espera: Completer<void>());

    await DisparadorBackupRespaldo(servicio).solicitar('col-1').timeout(const Duration(seconds: 1));

    expect(servicio.pedidos, hasLength(1));
  });
}
