import '../../domain/value_objects/punto_capturado.dart';

/// El permiso de ubicación del teléfono, ya traducido de lo que reporta el plugin.
enum PermisoUbicacion {
  concedido,

  /// Negado, pero todavía se puede volver a pedir.
  denegado,

  /// Negado para siempre: solo se cambia desde los ajustes de la app.
  denegadoParaSiempre,
}

/// Lo que la app le pide al plugin de GPS, en una sola costura para poder probar el adaptador
/// ([ProveedorGpsPlataforma]) sin un teléfono. La implementación real es
/// `PlataformaGpsGeolocator`.
abstract interface class PlataformaGps {
  /// La ubicación del teléfono está encendida.
  Future<bool> servicioActivo();

  Future<PermisoUbicacion> permiso();

  /// Muestra el cuadro del sistema que pide el permiso.
  Future<PermisoUbicacion> pedirPermiso();

  /// Una lectura del GPS. Lanza (`TimeoutException`, o lo que lance el plugin) si no llega a
  /// tiempo: el adaptador lo traduce.
  Future<LecturaGps> leer({required Duration limite});

  Future<void> abrirAjustesUbicacion();

  Future<void> abrirAjustesApp();
}
