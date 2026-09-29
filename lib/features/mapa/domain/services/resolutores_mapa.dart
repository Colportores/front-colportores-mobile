import 'package:equatable/equatable.dart';

import '../value_objects/coordenadas.dart';

/// De dónde salen los tiles del mapa (HU-UBI-003, ADR-011).
enum FuenteTiles {
  /// Paquete PMTiles descargado para la zona: funciona sin red y es lo priorizado.
  pmtilesOffline,

  /// Servidor de tiles online: fallback si la zona no está descargada.
  servidorOnline,

  /// Ni paquete ni servidor: la vista muestra el mapa en escala de grises con la advertencia
  /// "Sin tiles para esta zona. Descargá tu ciudad en Configuración."
  sinTiles,
}

/// Elige la [FuenteTiles]. Función pura: qué hay descargado y si hay red lo informan otros
/// (descarga de paquetes: SYNC-010, #189).
abstract final class ResolutorFuenteTiles {
  /// [servidorOnlineDisponible] es `false` si el servidor público rechaza (rate limit): se trata
  /// como sin red aunque haya conexión.
  static FuenteTiles resolver({
    required bool hayPaqueteOffline,
    required bool hayRed,
    bool servidorOnlineDisponible = true,
  }) {
    if (hayPaqueteOffline) return FuenteTiles.pmtilesOffline;
    if (hayRed && servidorOnlineDisponible) return FuenteTiles.servidorOnline;
    return FuenteTiles.sinTiles;
  }
}

/// De dónde sale el centro inicial del mapa.
enum OrigenCentroMapa { gps, ultimaCiudad, ciudadColportor }

/// Dónde se centra el mapa al abrirlo y si el botón "Mi ubicación" sirve.
final class CentroMapa extends Equatable {
  const CentroMapa({required this.coordenadas, required this.origen, required this.hayGps});

  final Coordenadas coordenadas;
  final OrigenCentroMapa origen;

  /// Hay posición GPS válida: si no, el botón "Mi ubicación" queda deshabilitado.
  final bool hayGps;

  @override
  List<Object?> get props => [coordenadas, origen, hayGps];
}

/// Resuelve el centro inicial del mapa: GPS, si hay; si no, la última ciudad usada; si no, la
/// ciudad del colportor. Una posición en (0, 0) o fuera de rango cuenta como sin GPS.
///
/// Los centros de las ciudades los aporta quien llama: hoy no hay tabla local de ciudades con
/// coordenadas (ver el comentario del issue #198).
abstract final class ResolutorCentroMapa {
  /// `null` si no hay ninguna de las tres: la vista decide qué mostrar.
  static CentroMapa? resolver({
    Coordenadas? gps,
    Coordenadas? centroUltimaCiudad,
    Coordenadas? centroCiudadColportor,
  }) {
    final gpsValido = gps != null && !gps.sonCero && gps.estanEnRango && gps.lat.isFinite;
    if (gpsValido && gps.lon.isFinite) {
      return CentroMapa(coordenadas: gps, origen: OrigenCentroMapa.gps, hayGps: true);
    }
    final ultima = _valido(centroUltimaCiudad);
    if (ultima != null) {
      return CentroMapa(coordenadas: ultima, origen: OrigenCentroMapa.ultimaCiudad, hayGps: false);
    }
    final ciudad = _valido(centroCiudadColportor);
    if (ciudad != null) {
      return CentroMapa(
        coordenadas: ciudad,
        origen: OrigenCentroMapa.ciudadColportor,
        hayGps: false,
      );
    }
    return null;
  }

  static Coordenadas? _valido(Coordenadas? c) =>
      c != null && c.lat.isFinite && c.lon.isFinite && c.estanEnRango ? c : null;
}
