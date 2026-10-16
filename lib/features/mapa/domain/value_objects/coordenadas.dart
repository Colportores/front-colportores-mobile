import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Punto geográfico en grados decimales (WGS84, lo que da el GPS del teléfono).
///
/// No valida en el constructor: una lectura fuera de rango o en `(0, 0)` es un dato que llega del
/// GPS o del mapa y el caso de uso lo tiene que poder rechazar con un `Failure`, no con una
/// excepción (convenciones §4.3).
final class Coordenadas extends Equatable {
  const Coordenadas({required this.lat, required this.lon});

  final double lat;
  final double lon;

  /// Radio medio de la Tierra en metros (el de la fórmula de haversine).
  static const radioTierraMetros = 6371008.8;

  /// Los rangos del `CHECK` de `public.ubicacion` (backend-supabase 0001).
  bool get estanEnRango => lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;

  /// `(0, 0)`: lo que reportan algunos GPS sin fix. HU-UBI-001 lo trata como sin GPS.
  bool get sonCero => lat == 0 && lon == 0;

  /// Distancia en metros sobre la superficie (haversine). A la escala de RF-UB08 (unos metros) el error
  /// frente al elipsoide es de milímetros.
  double distanciaMetrosA(Coordenadas otra) {
    double rad(double grados) => grados * math.pi / 180;
    final dLat = rad(otra.lat - lat);
    final dLon = rad(otra.lon - lon);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(otra.lat)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * radioTierraMetros * math.asin(math.min(1, math.sqrt(a)));
  }

  @override
  List<Object?> get props => [lat, lon];
}
