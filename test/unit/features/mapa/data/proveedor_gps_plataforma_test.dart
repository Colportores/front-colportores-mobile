import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/services/plataforma_gps.dart';
import 'package:colportores_mobile/features/mapa/data/services/proveedor_gps_plataforma.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Plataforma implements PlataformaGps {
  var activo = true;
  var permisoActual = PermisoUbicacion.concedido;
  var permisoTrasPedir = PermisoUbicacion.concedido;
  Object? falla;
  var lectura = const LecturaGps(
    coordenadas: Coordenadas(lat: -34.9, lon: -56.1),
    precisionMetros: 8,
  );
  var pedidos = 0;
  var ajustesUbicacion = 0;
  var ajustesApp = 0;

  @override
  Future<bool> servicioActivo() async => activo;

  @override
  Future<PermisoUbicacion> permiso() async => permisoActual;

  @override
  Future<PermisoUbicacion> pedirPermiso() async {
    pedidos++;
    permisoActual = permisoTrasPedir;
    return permisoTrasPedir;
  }

  @override
  Future<LecturaGps> leer({required Duration limite}) async {
    if (falla != null) throw falla!;
    return lectura;
  }

  @override
  Future<void> abrirAjustesUbicacion() async => ajustesUbicacion++;

  @override
  Future<void> abrirAjustesApp() async => ajustesApp++;
}

MotivoSinGps? _motivo(Either<Failure, LecturaGps> resultado) =>
    resultado.fold((f) => f is FailureGpsNoDisponible ? f.motivo : null, (_) => null);

void main() {
  late _Plataforma plataforma;
  late ProveedorGpsPlataforma gps;

  setUp(() {
    plataforma = _Plataforma();
    gps = ProveedorGpsPlataforma(plataforma);
  });

  group('posicionActual', () {
    test('con servicio y permiso, devuelve la lectura con su precisión', () async {
      final r = await gps.posicionActual();
      expect(r, Right<Failure, LecturaGps>(plataforma.lectura));
      expect(plataforma.pedidos, 0);
    });

    test('con la ubicación apagada: servicioApagado, sin pedir permiso', () async {
      plataforma.activo = false;
      expect(_motivo(await gps.posicionActual()), MotivoSinGps.servicioApagado);
      expect(plataforma.pedidos, 0);
    });

    test('permiso denegado pero pedible: lo pide, y si lo dan, lee', () async {
      plataforma.permisoActual = PermisoUbicacion.denegado;
      final r = await gps.posicionActual();
      expect(plataforma.pedidos, 1);
      expect(r.isRight(), isTrue);
    });

    test('permiso denegado y lo vuelven a negar: permisoDenegado', () async {
      plataforma.permisoActual = PermisoUbicacion.denegado;
      plataforma.permisoTrasPedir = PermisoUbicacion.denegado;
      expect(_motivo(await gps.posicionActual()), MotivoSinGps.permisoDenegado);
    });

    test('permiso negado para siempre: permisoDenegado, sin volver a pedirlo', () async {
      plataforma.permisoActual = PermisoUbicacion.denegadoParaSiempre;
      expect(_motivo(await gps.posicionActual()), MotivoSinGps.permisoDenegado);
      expect(plataforma.pedidos, 0);
    });

    test('una lectura que se agota o falla es sinSenal y no lanza', () async {
      plataforma.falla = TimeoutException('sin señal');
      expect(_motivo(await gps.posicionActual()), MotivoSinGps.sinSenal);
      plataforma.falla = StateError('plugin');
      expect(_motivo(await gps.posicionActual()), MotivoSinGps.sinSenal);
    });
  });

  group('activar', () {
    test('con la ubicación apagada abre los ajustes de ubicación', () async {
      await gps.activar(MotivoSinGps.servicioApagado);
      expect(plataforma.ajustesUbicacion, 1);
      expect(plataforma.ajustesApp, 0);
    });

    test('con el permiso denegado pero pedible, lo pide', () async {
      plataforma.permisoActual = PermisoUbicacion.denegado;
      await gps.activar(MotivoSinGps.permisoDenegado);
      expect(plataforma.pedidos, 1);
      expect(plataforma.ajustesApp, 0);
    });

    test('con el permiso negado para siempre, abre los ajustes de la app', () async {
      plataforma.permisoActual = PermisoUbicacion.denegadoParaSiempre;
      await gps.activar(MotivoSinGps.permisoDenegado);
      expect(plataforma.pedidos, 0);
      expect(plataforma.ajustesApp, 1);
    });

    test('si lo piden y lo niegan para siempre, abre los ajustes de la app', () async {
      plataforma.permisoActual = PermisoUbicacion.denegado;
      plataforma.permisoTrasPedir = PermisoUbicacion.denegadoParaSiempre;
      await gps.activar(MotivoSinGps.permisoDenegado);
      expect(plataforma.ajustesApp, 1);
    });

    test('sin señal no hay nada que activar', () async {
      await gps.activar(MotivoSinGps.sinSenal);
      expect(plataforma.pedidos + plataforma.ajustesApp + plataforma.ajustesUbicacion, 0);
    });
  });
}
