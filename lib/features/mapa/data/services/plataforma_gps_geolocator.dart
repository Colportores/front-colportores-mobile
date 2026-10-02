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
