import 'package:geolocator/geolocator.dart';

import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';
import 'plataforma_gps.dart';

/// [PlataformaGps] sobre `geolocator` (ADR-009, HU-UBI-001). Delgada a propósito: no decide nada,
/// solo traduce. No se puede probar en Docker (necesita el plugin nativo): la prueba manual en un
/// teléfono Android es parte de la definición de terminado.
final class PlataformaGpsGeolocator implements PlataformaGps {
  const PlataformaGpsGeolocator();

  @override
  Future<bool> servicioActivo() => Geolocator.isLocationServiceEnabled();

  @override
  Future<PermisoUbicacion> permiso() async => _traducir(await Geolocator.checkPermission());

  @override
  Future<PermisoUbicacion> pedirPermiso() async => _traducir(await Geolocator.requestPermission());

  @override
  Future<LecturaGps> leer({required Duration limite}) async {
    final posicion = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: limite),
    );
    return LecturaGps(
      coordenadas: Coordenadas(lat: posicion.latitude, lon: posicion.longitude),
      precisionMetros: posicion.accuracy,
    );
  }

  /// Cada cuántos metros que se mueve el teléfono el sistema avisa una posición nueva: lo justo para
  /// que el mapa siga a quien camina sin despertar el GPS a cada paso (batería, #670).
  static const distanciaMinimaMetros = 3;

  /// Por debajo de esta velocidad (m/s) el rumbo del sistema no vale: un teléfono quieto, o casi,
  /// reporta un rumbo cualquiera (0 en Android, -1 en iOS) y el mapa giraría solo.
  static const velocidadMinimaParaRumbo = 0.5;

  @override
  Stream<LecturaGps> seguir() =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: distanciaMinimaMetros,
        ),
      ).map(
        (posicion) => LecturaGps(
          coordenadas: Coordenadas(lat: posicion.latitude, lon: posicion.longitude),
          precisionMetros: posicion.accuracy,
          rumboGrados: rumboDe(rumbo: posicion.heading, velocidad: posicion.speed),
        ),
      );

  /// El rumbo del sistema, en grados (0 ≤ rumbo < 360), o `null` si no vale: viene fuera de rango
  /// o el teléfono casi no se mueve ([velocidadMinimaParaRumbo]).
  static double? rumboDe({required double rumbo, required double velocidad}) {
    if (!rumbo.isFinite || !velocidad.isFinite) return null;
    if (rumbo < 0 || rumbo >= 360 || velocidad < velocidadMinimaParaRumbo) return null;
    return rumbo;
  }

  @override
  Future<void> abrirAjustesUbicacion() => Geolocator.openLocationSettings();

  @override
  Future<void> abrirAjustesApp() => Geolocator.openAppSettings();

  static PermisoUbicacion _traducir(LocationPermission permiso) => switch (permiso) {
    LocationPermission.always || LocationPermission.whileInUse => PermisoUbicacion.concedido,
    LocationPermission.deniedForever => PermisoUbicacion.denegadoParaSiempre,
    LocationPermission.denied || LocationPermission.unableToDetermine => PermisoUbicacion.denegado,
  };
}
