// QA de #679 («Activar GPS» no hacía nada tras negar el permiso): secuencias de permiso que el
// adaptador tiene que resolver sin volver a pedir a ciegas y sin dejar al colportor sin salida.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/services/plataforma_gps.dart';
import 'package:colportores_mobile/features/mapa/data/services/proveedor_gps_plataforma.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

/// Como Android: mirar el permiso nunca dice «para siempre»; eso solo sale de pedirlo.
final class _AndroidFalso implements PlataformaGps {
  var servicio = true;
  var enAjustes = PermisoUbicacion.denegado;
  var respuestaAlPedir = PermisoUbicacion.denegadoParaSiempre;
  var pedidos = 0;
  var ajustesApp = 0;

  @override
  Future<bool> servicioActivo() async => servicio;

  @override
  Future<PermisoUbicacion> permiso() async =>
      enAjustes == PermisoUbicacion.denegadoParaSiempre ? PermisoUbicacion.denegado : enAjustes;

  @override
  Future<PermisoUbicacion> pedirPermiso() async {
    pedidos++;
    enAjustes = respuestaAlPedir;
    return respuestaAlPedir;
  }

  @override
  Future<LecturaGps> leer({required Duration limite}) async =>
      const LecturaGps(coordenadas: Coordenadas(lat: -34.9, lon: -56.1), precisionMetros: 8);

  @override
  Stream<LecturaGps> seguir() => const Stream.empty();

  @override
  Future<void> abrirAjustesUbicacion() async {}

  @override
  Future<void> abrirAjustesApp() async => ajustesApp++;
}

bool _leyo(Either<Failure, LecturaGps> r) => r.isRight();

void main() {
  late _AndroidFalso android;
  late ProveedorGpsPlataforma gps;

  setUp(() {
    android = _AndroidFalso();
    gps = ProveedorGpsPlataforma(android);
  });

  test(
    'dado «para siempre», cuando se lee muchas veces, el sistema se consulta una sola vez',
    () async {
      for (var i = 0; i < 6; i++) {
        expect(_leyo(await gps.posicionActual()), isFalse);
      }
      expect(android.pedidos, 1);
    },
  );

  test('dado «para siempre», cuando toca «Activar GPS» varias veces, cada toque vuelve a pedir y '
      'abre los ajustes de la app (la salida siempre está)', () async {
    await gps.posicionActual();
    await gps.activar(MotivoSinGps.permisoDenegado);
    await gps.activar(MotivoSinGps.permisoDenegado);

    expect(android.pedidos, 3);
    expect(android.ajustesApp, 2);
  });

  test('dado «para siempre», cuando lo concede en los ajustes de la app, la lectura siguiente '
      'sale bien sin pedir nada', () async {
    await gps.posicionActual();
    android.enAjustes = PermisoUbicacion.concedido;

    expect(_leyo(await gps.posicionActual()), isTrue);
    expect(android.pedidos, 1);
  });

  test('dado un permiso concedido que después se quita en los ajustes, cuando se lee, el '
      'adaptador vuelve a preguntar (no queda con la marca vieja)', () async {
    await gps.posicionActual();
    android.enAjustes = PermisoUbicacion.concedido;
    await gps.posicionActual();
    android.enAjustes = PermisoUbicacion.denegado;
    android.respuestaAlPedir = PermisoUbicacion.concedido;

    expect(_leyo(await gps.posicionActual()), isTrue);
    expect(android.pedidos, 2);
  });

  test('dado un «no» común (sin «para siempre»), cuando se lee de nuevo, vuelve a pedir', () async {
    android.respuestaAlPedir = PermisoUbicacion.denegado;
    await gps.posicionActual();
    await gps.posicionActual();

    expect(android.pedidos, 2);
  });

  test('dado «para siempre», cuando concede tras «Activar GPS» (ajustes y vuelta), la lectura '
      'sale y no se abre nada de más', () async {
    await gps.posicionActual();
    await gps.activar(MotivoSinGps.permisoDenegado);
    expect(android.ajustesApp, 1);
    android.enAjustes = PermisoUbicacion.concedido;

    expect(_leyo(await gps.posicionActual()), isTrue);
    expect(android.ajustesApp, 1);
  });

  test('dado el servicio de ubicación apagado, cuando se lee, no pide el permiso', () async {
    android.servicio = false;
    final r = await gps.posicionActual();

    expect(
      r.fold((f) => (f as FailureGpsNoDisponible).motivo, (_) => null),
      MotivoSinGps.servicioApagado,
    );
    expect(android.pedidos, 0);
  });
}
