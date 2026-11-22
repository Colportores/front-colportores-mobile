// QA #674 (HU-UBI-003, privacidad §7.5): el seguimiento del GPS no deja coordenadas ni texto del
// error del plugin en los logs, ni en el `toString()` de la lectura.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/services/plataforma_gps.dart';
import 'package:colportores_mobile/features/mapa/data/services/proveedor_gps_plataforma.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

final class _Plataforma implements PlataformaGps {
  final seguimiento = StreamController<LecturaGps>();

  @override
  Future<bool> servicioActivo() async => true;

  @override
  Future<PermisoUbicacion> permiso() async => PermisoUbicacion.concedido;

  @override
  Future<PermisoUbicacion> pedirPermiso() async => PermisoUbicacion.concedido;

  @override
  Future<LecturaGps> leer({required Duration limite}) async => throw UnimplementedError();

  @override
  Stream<LecturaGps> seguir() => seguimiento.stream;

  @override
  Future<void> abrirAjustesUbicacion() async {}

  @override
  Future<void> abrirAjustesApp() async {}
}

void main() {
  const secreto = 'Ana Pérez 099123456 Mataojo 2044 -34.88761 -56.13024';

  test('dado un plugin que falla con un mensaje con datos personales, cuando el seguimiento se '
      'corta, entonces el log solo dice el tipo de la causa', () async {
    final salida = MemoryOutput();
    final plataforma = _Plataforma();
    final gps = ProveedorGpsPlataforma(
      plataforma,
      logger: AppLogger(
        logger: Logger(level: Level.all, printer: SimplePrinter(), output: salida),
      ),
    );

    final recibidos = <Either<Failure, LecturaGps>>[];
    final suscripcion = gps.seguir().listen(recibidos.add);
    await pumpEventQueue();
    plataforma.seguimiento.add(
      const LecturaGps(
        coordenadas: Coordenadas(lat: -34.88761, lon: -56.13024),
        precisionMetros: 5,
      ),
    );
    plataforma.seguimiento.addError(Exception(secreto));
    await pumpEventQueue();
    await suscripcion.cancel();

    final logs = salida.buffer.expand((e) => e.lines).join('\n');
    expect(logs, isNotEmpty, reason: 'el corte se registra');
    for (final dato in ['Ana', '099123456', 'Mataojo', '-34.88761', '-56.13024']) {
      expect(logs, isNot(contains(dato)));
    }
    expect(recibidos.last.isLeft(), isTrue);
  });

  test('la lectura con rumbo no imprime la posición en su toString (stringify apagado)', () {
    expect(EquatableConfig.stringify, isFalse);
    const lectura = LecturaGps(
      coordenadas: Coordenadas(lat: -34.88761, lon: -56.13024),
      precisionMetros: 5,
      rumboGrados: 90,
    );
    expect(lectura.toString(), isNot(contains('-34.88761')));
    expect(lectura.toString(), isNot(contains('-56.13024')));
  });
}
